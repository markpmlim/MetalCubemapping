//
//  Renderer.swift
//  Cubemap2EquiRect
//
//  Created by Mark Lim Pak Mun on 11/11/2020.
//  Copyright © 2020 Mark Lim Pak Mun. All rights reserved.
//

import MetalKit
import AppKit

struct Uniforms {
    var mvpMatrix: float4x4
}

class Renderer : NSObject, MTKViewDelegate {

    weak var view: MTKView!
    let commandQueue: MTLCommandQueue!
    var offscreenPipelineState: MTLRenderPipelineState!
    var quadPipelineState: MTLRenderPipelineState!
    var quadBuffer: MTLBuffer!
    let device: MTLDevice!
    var time: Float = 0
    var samplerState: MTLSamplerState!
    var cubeMapTexture: MTLTexture!
    var offScreenRenderPassDescriptor: MTLRenderPassDescriptor!
    var equiRectangularTexture: MTLTexture!
    var equiRectMapWidth: Int = 0
    // size = 24 bytes; alignment=16; stride=32
    struct CubeVertex {
        let position: float4    // 16 bytes
        let uv: float2          //  8 bytes
   }

    struct QuadVertex {
        var position: float2
        var texCoord: float2
    }

    init?(view: MTKView,
          device: MTLDevice) {
        self.view = view
        
        view.clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0)
        self.device = device
        commandQueue = device.makeCommandQueue()
 
        super.init()
        view.delegate = self
        view.device = device

        buildResources()
        buildRenderPipelinesWithDevice(device: device,
                                       view: self.view)
        createEquiRectangularTexture()

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }


    func buildResources() {
        // The following images cannot be stored in an Asset.xcassets because their filetype is hdr.
        // They were obtained by running an OpenGL program and their bitmaps written out
        // in RGBE format. Currently macOS (10.15) does not support writing HDR files natively.
        let bundle = Bundle.main
        let names = ["image00", "image01", "image02", "image03", "image04", "image05"]
        var faceTextures = [MTLTexture]()
        for name in names {
            let url = bundle.url(forResource: name,
                                 withExtension: "hdr")
            let hdrTexture = loadTextureAsRGBA16Float(url!,
                                                      device: self.device)
            faceTextures.append(hdrTexture!)
        }
        // We expect the cube's width, height and length of equal.
        let imageWidth = faceTextures[0].width
        let imageHeight = faceTextures[0].height
        equiRectMapWidth = imageWidth
        let textureDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float,
                                                                            size: imageWidth, mipmapped: false)
        cubeMapTexture = view.device!.makeTexture(descriptor: textureDescriptor)!
        let region = MTLRegionMake2D(0, 0,
                                      imageWidth, imageHeight)
        let bytesPerPixel = 8
        let bytesPerRow = bytesPerPixel * imageWidth
        let bytesPerImage = bytesPerRow * imageHeight
        for i in 0..<faceTextures.count {
            // Currently, macOS does not the primitive type half floats; however, MSL does.
            // A half float has the same size as a UInt16.
            let destPixels = UnsafeMutablePointer<UInt16>.allocate(capacity: 4 * imageWidth * imageHeight)
            faceTextures[i].getBytes(destPixels,
                                     bytesPerRow: bytesPerRow,
                                     from: region,
                                     mipmapLevel: 0)
            cubeMapTexture.replace(region: region,
                                   mipmapLevel: 0,
                                   slice: i,
                                   withBytes: destPixels,
                                   bytesPerRow: bytesPerRow,
                                   bytesPerImage: bytesPerImage)
            destPixels.deallocate()
        }

        // The offscreen generated texture will be displayed using this geometry.
        // The ratio of the width to height of the quad = 2:1.
        // The rectangle rendered must fit the currenDrawable's size.
        // The idea is no matter how the user may resize the window,
        // its contents will fill the entire view.
        let quadVertices: [QuadVertex] = [
            //              Positions                        TexCoords
            QuadVertex(position: float2(-2.0, -1.0), texCoord: float2(0.0, 1.0)),
            QuadVertex(position: float2(-2.0,  1.0), texCoord: float2(0.0, 0.0)),
            QuadVertex(position: float2( 2.0, -1.0), texCoord: float2(1.0, 1.0)),
            QuadVertex(position: float2( 2.0,  1.0), texCoord: float2(1.0, 0.0))
        ]
        quadBuffer = device.makeBuffer(bytes: quadVertices,
                                       length: MemoryLayout<QuadVertex>.stride * quadVertices.count,
                                       options: [])
    }

    func buildRenderPipelinesWithDevice(device: MTLDevice,
                                        view: MTKView) {

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = MTLVertexFormat.float2; // position
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = MTLVertexFormat.float2; // texCoords
        vertexDescriptor.attributes[1].offset = 2 * MemoryLayout<Float>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.perVertex
        vertexDescriptor.layouts[0].stride = 4 * MemoryLayout<Float>.stride

        guard let library = device.makeDefaultLibrary()
        else {
            fatalError("Could not load default library from main bundle")
        }
        // This pipeline state will be used to display the generated texture.
        let quadPipelineDescriptor = MTLRenderPipelineDescriptor()
        quadPipelineDescriptor.label = "Drawable Render Pipeline"
        // Load the vertex program into the library
        let quadVertexProgram = library.makeFunction(name: "simpleVertexShader")
        // Load the fragment program into the library
        let quadFragmentProgram = library.makeFunction(name: "simpleFragmentShader")
        quadPipelineDescriptor.sampleCount = view.sampleCount
        quadPipelineDescriptor.vertexFunction = quadVertexProgram
        quadPipelineDescriptor.fragmentFunction = quadFragmentProgram
        quadPipelineDescriptor.vertexDescriptor = vertexDescriptor
        quadPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        quadPipelineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        do {
            try quadPipelineState = device.makeRenderPipelineState(descriptor: quadPipelineDescriptor)
        }
        catch let error {
            Swift.print("Failed to created quad pipeline state - error:", error)
        }
        //////////
        // Need another pipeline state to render the 1:1 equirectangular map.
        let equiRectVertexProgram = library.makeFunction(name: "projectTexture")
        // Load the fragment program into the library
        let equiRectFragmentProgram = library.makeFunction(name: "outputEquiRectangularTexture")
        quadPipelineDescriptor.label = "Offscreen PipelineState"
        quadPipelineDescriptor.vertexFunction = equiRectVertexProgram
        quadPipelineDescriptor.fragmentFunction = equiRectFragmentProgram
        quadPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        // The geometry (a 2x2 quad) is embedded in the vertex function.
        quadPipelineDescriptor.vertexDescriptor = nil
        do {
            try offscreenPipelineState = device.makeRenderPipelineState(descriptor: quadPipelineDescriptor)
        }
        catch let error {
            Swift.print("Failed to created offscreen pipeline state - error:", error)
        }

        let texDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: view.colorPixelFormat,
                                                                     width: equiRectMapWidth, height: equiRectMapWidth,
                                                                     mipmapped: false)
        // Set up a texture for rendering to and sampling from.
        texDescriptor.usage = [MTLTextureUsage.renderTarget, MTLTextureUsage.shaderRead];

        equiRectangularTexture = device.makeTexture(descriptor: texDescriptor)
        offScreenRenderPassDescriptor = MTLRenderPassDescriptor()
        offScreenRenderPassDescriptor.colorAttachments[0].texture = equiRectangularTexture
        offScreenRenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadAction.clear;
        offScreenRenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 1, 1)
        offScreenRenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreAction.store;
    }

    // Generate a 2D texture whose dimensions are 1:1.
    func createEquiRectangularTexture() {
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.addCompletedHandler {
                cb in
                if commandBuffer.status == .completed {
                    print("The texture of EquiRectangular Map is ready")
                }
                else {
                    if commandBuffer.status == .error {
                        print("The textures of EquiRectangular Map could be not created")
                        print("Command Buffer Status Error")
                    }
                    else {
                        print("Command Buffer Status Code: ", commandBuffer.status)
                    }
                }
            }

            // Setup for an offscreen render pass.
            let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: offScreenRenderPassDescriptor)!
            commandEncoder.label = "Offscreen Render Pass"
            commandEncoder.setRenderPipelineState(offscreenPipelineState)
            let viewPort = MTLViewport(originX: 0, originY: 0,
                                       width: Double(equiRectMapWidth), height: Double(equiRectMapWidth),
                                       znear: 0, zfar: 1)
            commandEncoder.setViewport(viewPort)
            commandEncoder.setFragmentTexture(cubeMapTexture,
                                              index: 0)
            commandEncoder.drawPrimitives(type: .triangleStrip,
                                          vertexStart: 0,
                                          vertexCount: 4)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }

    // Implementation of the 2 MTKView delegate methods.
    func mtkView(_ view: MTKView,
                        drawableSizeWillChange size: CGSize) {
    }

    // We don't need triple buffering because a static image is being rendered.
    func draw(in view: MTKView) {
        if  let commandBuffer = commandQueue.makeCommandBuffer(),
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable {
            commandBuffer.label = "Drawable Texture"

            let renderQuadEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderQuadEncoder.setRenderPipelineState(quadPipelineState)
            renderQuadEncoder.setFrontFacing(.clockwise)
            // Note: the geometry is a 2:1 quad.
            renderQuadEncoder.setVertexBuffer(quadBuffer,
                                              offset: 0,
                                              index: 0)
            // The scaling matrix when applied to the 2:1 quad will transform
            // it into a 1:1 quad.
            var scalingMatrix = float2x2(columns: (float2(0.5,0), float2(0,1)))
            renderQuadEncoder.setVertexBytes(&scalingMatrix,
                                             length: MemoryLayout<float2x2>.stride,
                                             index: 1)
 
            renderQuadEncoder.setFragmentTexture(equiRectangularTexture,
                                                 index: 0)
            renderQuadEncoder.drawPrimitives(type: .triangleStrip,
                                             vertexStart: 0,
                                             vertexCount: 4)

            renderQuadEncoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }
}
 
