//
//  CubemapRenderer.swift
//  MetalCubemapping
//
//  Created by Mark Lim Pak Mun on 27/08/2020.
//  Copyright © 2020 Mark Lim Pak Mun. All rights reserved.
//

import Foundation
import MetalKit
import SceneKit
import SceneKit.ModelIO
import simd

// Global constants
let kMaxInFlightFrameCount = 3
let kAlignedUniformsSize = (MemoryLayout<Uniforms>.stride & ~0xFF) + 0x100

struct Uniforms {
    var modelMatrix = matrix_identity_float4x4
    var viewMatrix = matrix_identity_float4x4
    var projectionMatrix = matrix_identity_float4x4
    var normalMatrix = matrix_identity_float4x4
    var worldCameraPosition = float4(0)
}

class CubemapRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let mtkView: MTKView
    let commandQueue: MTLCommandQueue!
    var defaultLibrary: MTLLibrary!
    let frameSemaphore = DispatchSemaphore(value: kMaxInFlightFrameCount)
    var currentFrameIndex = 0

    var viewMatrix: float4x4!
    var projectionMatrix: float4x4!
    var time: Float = 0.0
    
    var vertexDescriptor: MTLVertexDescriptor!
    var torusRenderPipelineState: MTLRenderPipelineState!
    var skyboxRenderPipelineState: MTLRenderPipelineState!
    var renderToTextureRenderPipelineState: MTLRenderPipelineState!

    var torusMesh: Mesh!
    var skyboxMesh: Mesh!
    var uniformsBuffers = [MTLBuffer]()

    var skyBoxTextures = [MTLTexture?]()
    var cubeMapTexture: MTLTexture!
    var cubeMapDepthTexture: MTLTexture!
    var depthTexture: MTLTexture!

    var renderToTexturePassDescriptor: MTLRenderPassDescriptor!
    var skyboxDepthStencilState: MTLDepthStencilState!
    var torusDepthStencilState: MTLDepthStencilState!

    init(view: MTKView, device: MTLDevice) {
        self.mtkView = view
        self.device = device
        // Create a new command queue
        self.commandQueue = device.makeCommandQueue()

        super.init()

        buildResources()
        buildPipelines()
        // Note: Don't write to the skybox's depth attachment
        skyboxDepthStencilState = buildDepthStencilState(device: device,
                                                         isWriteEnabled: false)
        torusDepthStencilState = buildDepthStencilState(device: device,
                                                        isWriteEnabled: true)
        createCubemapTexture()
    }

    deinit {
        for _ in 0..<kMaxInFlightFrameCount {
            self.frameSemaphore.signal()
        }
    }

    func buildResources() {
        skyboxMesh = BoxMesh(withSize: 2,
                             device: device)
        // Setup the various objects
        torusMesh = TorusMesh(ringRadius: 3.0, pipeRadius: 1.0,
                              device: device)!

        for _ in 0..<kMaxInFlightFrameCount {
            // Allocate memory for 2 blocks of Uniforms.
            let buffer = self.device.makeBuffer(length: kAlignedUniformsSize * 2,
                                                options: .cpuCacheModeWriteCombined)
            uniformsBuffers.append(buffer!)
        }

        // Load the individual graphic that will be used as a cubemap texture.
        // Assumes the graphic images have the same dimensions.
        // The images are in the folder Assets.xcassets.
        var nsImages = [NSImage]()
        for i in 0..<6 {
            let name = "image" + String(i)
            let image = NSImage(named: NSImage.Name(name))
            nsImages.append(image!)
        }

        // Array of 2D MTLTextures which will be used to setup the cube map texture.
        skyBoxTextures = [MTLTexture?]()
        let textureLoader = MTKTextureLoader(device: device)
        let options = [ convertFromMTKTextureLoaderOption(MTKTextureLoader.Option.SRGB)      : NSNumber(value: false),
                        convertFromMTKTextureLoaderOrigin(MTKTextureLoader.Origin.bottomLeft): NSNumber(value: false)]
        for nsImage in nsImages {
            let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            var texture: MTLTexture
            do {
                texture = try textureLoader.newTexture(cgImage: cgImage!,
                                                       options: convertToOptionalMTKTextureLoaderOptionDictionary(options))
            }
            catch  {
                fatalError("Can't instantiate the metal textures: \(error)")
            }
            skyBoxTextures.append(texture)
        }
        let cubemapResolution = nsImages[0].size.width
        // Set up a cubemap texture for rendering to and sampling from
        // using the concept of layer rendering.
        let cubeMapDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: mtkView.colorPixelFormat,
                                                                     size: Int(cubemapResolution),
                                                                     mipmapped: false)
        cubeMapDesc.storageMode = MTLStorageMode.private
        cubeMapDesc.usage = [MTLTextureUsage.renderTarget, MTLTextureUsage.shaderRead]
        cubeMapTexture = device.makeTexture(descriptor: cubeMapDesc)

    /*
        let cubeMapDepthDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: MTLPixelFormat.depth32Float,
                                                                          size: Int(cubemapResolution),
                                                                          mipmapped: false)
        cubeMapDepthDesc.storageMode = MTLStorageMode.private
        cubeMapDepthDesc.usage = MTLTextureUsage.renderTarget
        cubeMapDepthTexture = device.makeTexture(descriptor: cubeMapDepthDesc)
    */
        // Set up a render pass descriptor for the render pass to render into the cubemap texture.
        renderToTexturePassDescriptor = MTLRenderPassDescriptor()
        renderToTexturePassDescriptor.colorAttachments[0].clearColor  = MTLClearColorMake(1, 1, 1, 1)
        renderToTexturePassDescriptor.colorAttachments[0].loadAction  = MTLLoadAction.clear
        renderToTexturePassDescriptor.colorAttachments[0].storeAction = MTLStoreAction.store
        renderToTexturePassDescriptor.depthAttachment.clearDepth      = 1.0
        renderToTexturePassDescriptor.depthAttachment.loadAction      = MTLLoadAction.clear

        renderToTexturePassDescriptor.colorAttachments[0].texture     = cubeMapTexture
        // No depth textures are needed.
        renderToTexturePassDescriptor.depthAttachment.texture         = nil
        renderToTexturePassDescriptor.renderTargetArrayLength         = 6
   }

    func buildPipelines() {
        // Load all the shader files with a metal file extension in the project
        guard let library = device.makeDefaultLibrary()
        else {
            fatalError("Could not load default library from main bundle")
        }
       
        // Create the render pipeline for the drawable render pass.
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Render Torus Pipeline"
        // The following assignment is necessary when layered rendering is enabled.
        pipelineDescriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClass.triangle
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "ReflectionVertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "CubeLookupShader")

        pipelineDescriptor.sampleCount = mtkView.sampleCount
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        pipelineDescriptor.vertexDescriptor = torusMesh.vertexDescriptor

        do {
            torusRenderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            fatalError("Could not create torus render pipeline state object: \(error)")
        }

        // Re-use the pipeline descriptor
        pipelineDescriptor.label = "Render Skybox Pipeline"
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "SkyboxVertexShader")
        // The fragmentFunction is "CubeLookupShader"
        pipelineDescriptor.vertexDescriptor = skyboxMesh.vertexDescriptor
        do {
             skyboxRenderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
         }
         catch {
             fatalError("Could not create skybox render pipeline state object: \(error)")
        }

        // Set up pipeline for rendering to the offscreen texture.
        // Reuse the above descriptor object and change properties that differ.
        pipelineDescriptor.label = "Offscreen Render Pipeline"
        pipelineDescriptor.sampleCount = 1
        pipelineDescriptor.colorAttachments[0].pixelFormat = cubeMapTexture.pixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.invalid
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "projectTexture")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "outputCubeMapTexture")
        // The geometry of the shape (a triangle strip) is embedded within the vertex function.
        pipelineDescriptor.vertexDescriptor = nil
        do {
            renderToTextureRenderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            fatalError("Could not create offscreen render pipeline state object: \(error)")
        }
    }

    func buildDepthStencilState(device: MTLDevice,
                                isWriteEnabled: Bool) -> MTLDepthStencilState? {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = isWriteEnabled
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }

    func buildDepthBuffer() {
        let drawableSize = mtkView.drawableSize
        let depthTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,
                                                                    width: Int(drawableSize.width),
                                                                    height: Int(drawableSize.height),
                                                                    mipmapped: false)
        depthTexDesc.resourceOptions = .storageModePrivate
        depthTexDesc.usage = [.renderTarget, .shaderRead]
        self.depthTexture = self.device.makeTexture(descriptor: depthTexDesc)
    }

    // Render to an offscreen cube map texture.
    func createCubemapTexture() {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        commandBuffer.addCompletedHandler {
            cb in
            if commandBuffer.status == .completed {
                print("The Cube Map Texture was created successfully.")
            }
            else {
                if commandBuffer.status == .error {
                    print("The Cube Map Texture could be not created")
                    print("Command Buffer Status Error")
                }
                else {
                    print("Command Buffer Status Code: ", commandBuffer.status)
                }
            }
        }

        let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderToTexturePassDescriptor)!
        commandEncoder.label = "Offscreen Render Pass"
        commandEncoder.setRenderPipelineState(renderToTextureRenderPipelineState)
        let range: Range<Int> = Range(0..<6)
        //let range = 0..<6
        commandEncoder.setFragmentTextures(skyBoxTextures, range: range)
        commandEncoder.drawPrimitives(type: MTLPrimitiveType.triangleStrip,
                                      vertexStart: 0,
                                      vertexCount: 4,
                                      instanceCount: 6)
        // End encoding commands for this render pass.
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    func updateUniforms() {
        time += 1 / Float(mtkView.preferredFramesPerSecond)
        let angle = -time
        // The camera distance needs to be adjusted.
        let cameraDistance: Float = 10.0
        // Use a rotating camera.
        let worldCameraPosition = float4(cameraDistance * cos(angle),
                                         1.0,
                                         cameraDistance * sin(angle),
                                         1.0)
        // Setup a view matrix
        viewMatrix = matrix_look_at_right_hand(worldCameraPosition[0], worldCameraPosition[1], worldCameraPosition[2],
                                               0, 0, 0,
                                               0, 1, 0)

        let skyboxModelMatrix = matrix_identity_float4x4
        let skyboxViewMatrix = matrix4x4_rotation(angle,
                                                  vector_float3(1, 1, 1))
        let skyboxNormalMatrix = skyboxModelMatrix.inverse.transpose    // unused

        var skyboxUniforms = Uniforms(modelMatrix: skyboxModelMatrix,
                                      viewMatrix: skyboxViewMatrix,
                                      projectionMatrix: projectionMatrix,
                                      normalMatrix: skyboxNormalMatrix, // unused
                                      worldCameraPosition: float4(0))   // not used
        let bufferPointer = uniformsBuffers[currentFrameIndex].contents()
        memcpy(bufferPointer,
               &skyboxUniforms,
               kAlignedUniformsSize)

        let torusModelMatrix = matrix4x4_rotation(angle,
                                                  float3(1, 1, 1))
        // Pass the torus' normal matrix in world space
        let normalMatrix = torusModelMatrix.inverse.transpose
        let torusViewMatrix = viewMatrix * torusModelMatrix
        var torusUniforms = Uniforms(modelMatrix: torusModelMatrix,
                                     viewMatrix: torusViewMatrix,
                                     projectionMatrix: projectionMatrix,
                                     normalMatrix: normalMatrix,
                                     worldCameraPosition: worldCameraPosition)
        memcpy(bufferPointer + kAlignedUniformsSize,
               &torusUniforms,
               kAlignedUniformsSize)
    }

    // Called whenever the view size changes
    func mtkView(_ view: MTKView,
                 drawableSizeWillChange size: CGSize) {
        buildDepthBuffer()
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        projectionMatrix = matrix_perspective_right_hand(Float.pi / 3,
                                                         aspectRatio,
                                                         0.1, 1000)
    }

    // called per frame update
    func draw(in view: MTKView) {
        let commandBuffer = commandQueue.makeCommandBuffer()!

        if  let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable {
            let drawableSize = drawable.layer.drawableSize
            if (drawableSize.width != CGFloat(depthTexture.width) || drawableSize.height != CGFloat(depthTexture.height)) {
                buildDepthBuffer()
            }
            _ = frameSemaphore.wait(timeout: DispatchTime.distantFuture)

            updateUniforms()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1)

            renderPassDescriptor.depthAttachment.texture = self.depthTexture
            renderPassDescriptor.depthAttachment.loadAction = .clear
            renderPassDescriptor.depthAttachment.storeAction = .dontCare
            renderPassDescriptor.depthAttachment.clearDepth = 1
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderEncoder.setFrontFacing(.counterClockwise)
            renderEncoder.setCullMode(.back)

            renderEncoder.setRenderPipelineState(skyboxRenderPipelineState)
            renderEncoder.setDepthStencilState(skyboxDepthStencilState)
            renderEncoder.setVertexBuffer(skyboxMesh.vertexBuffer,
                                          offset: skyboxMesh.vertexBufferOffset,
                                          index: 0)
            let currentBuffer = uniformsBuffers[currentFrameIndex]
            renderEncoder.setVertexBuffer(currentBuffer,
                                          offset: 0,
                                          index: 1)

            renderEncoder.setFragmentTexture(cubeMapTexture,
                                             index: 0)

            renderEncoder.drawIndexedPrimitives(type: skyboxMesh.primitiveType,
                                                indexCount: skyboxMesh.indexCount,
                                                indexType: skyboxMesh.indexType,
                                                indexBuffer: skyboxMesh.indexBuffer,
                                                indexBufferOffset: skyboxMesh.indexBufferOffset)

            renderEncoder.setRenderPipelineState(torusRenderPipelineState)
            renderEncoder.setDepthStencilState(torusDepthStencilState)

            renderEncoder.setVertexBuffer(torusMesh.vertexBuffer,
                                          offset: torusMesh.vertexBufferOffset,
                                          index: 0)

            renderEncoder.setVertexBuffer(currentBuffer,
                                          offset: kAlignedUniformsSize,
                                          index: 1)

            renderEncoder.setFragmentTexture(cubeMapTexture,
                                             index: 0)

           // Issue the draw call to draw the indexed geometry of the mesh
            renderEncoder.drawIndexedPrimitives(type: torusMesh.primitiveType,
                                                indexCount: torusMesh.indexCount,
                                                indexType: torusMesh.indexType,
                                                indexBuffer: torusMesh.indexBuffer,
                                                indexBufferOffset: torusMesh.indexBufferOffset)

            renderEncoder.endEncoding()
            // use completion handler to signal the semaphore when this frame is completed allowing the encoding of the next frame to proceed
            // use capture list to avoid any retain cycles if the command buffer gets retained anywhere besides this stack frame
            commandBuffer.addCompletedHandler {
                [weak self] commandBuffer in
                if let strongSelf = self {
                    strongSelf.frameSemaphore.signal()
                    /*
                     value of status    name
                        0               notEnqueued
                        1               enqueued
                        2               committed
                        3               scheduled
                        4               completed
                        5               error
                     */
                    if commandBuffer.status == .error {
                        print("Command Buffer Status Error")
                    }
                }
                return
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        currentFrameIndex = (currentFrameIndex + 1) % kMaxInFlightFrameCount
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromMTKTextureLoaderOption(_ input: MTKTextureLoader.Option) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromMTKTextureLoaderOrigin(_ input: MTKTextureLoader.Origin) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalMTKTextureLoaderOptionDictionary(_ input: [String: Any]?) -> [MTKTextureLoader.Option: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (MTKTextureLoader.Option(rawValue: key), value)})
}
