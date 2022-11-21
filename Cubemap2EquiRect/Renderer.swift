/*
 The 6 images are correctly produced using online program at the link:
    https://matheowis.github.io/HDRI-to-CubeMap/
 Previously the images were rendered and saved by tweaking an OpenGL
 program written by Joey de Vries.
 */
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
    // Set the dimensions of the texture to be generated.
    // The width of an equirectangular images is always 2x its height.
    var equiRectMapWidth: Int = 1024
    var equiRectMapHeight: Int = 512

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
        // These can obtained by running an OpenGL program and their bitmaps written out
        //  in RGBE format. Currently macOS (10.15) does not support writing HDR files natively.
        //let names = ["image00.hdr", "image01.hdr", "image02.hdr", "image03.hdr", "image04.hdr", "image05.hdr"]
        // Filenames stored in the Resources folder of a macOS application are case-sensitive.
        let names = ["px.hdr", "nx.hdr", "py.hdr", "ny.hdr", "pz.hdr", "nz.hdr"]
        var faceTextures = [MTLTexture]()
        let textureLoader = MTKTextureLoader(device: self.device)
        var hdrTexture: MTLTexture?
        for name in names {
            do {
                hdrTexture = try textureLoader.newTexture(fromRadianceFile: name)
                faceTextures.append(hdrTexture!)
            }
            catch let error as NSError {
                Swift.print("Can't load hdr file:\(name) error:\(error)")
                exit(1)
            }
        }

        // We assume the widths and heights of the six 2D textures are equal.
        let imageWidth = faceTextures[0].width
        let imageHeight = faceTextures[0].height
        let textureDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float,
                                                                            size: imageWidth,
                                                                            mipmapped: false)
        cubeMapTexture = view.device!.makeTexture(descriptor: textureDescriptor)!
        let region = MTLRegionMake2D(0, 0,
                                      imageWidth, imageHeight)
        let bytesPerPixel = 8
        let bytesPerRow = bytesPerPixel * imageWidth
        let bytesPerImage = bytesPerRow * imageHeight
        for i in 0..<faceTextures.count {
            // Currently, Swift does not the primitive type half floats; however, MSL does.
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
        // The ratio of the width to height of the quad = 1:1.
        // The origin of the texture coordinate system of this quad is at its
        //  top left corner with the u-axis pointing to the right horizontally
        //  and the v-axis pointing vertically downwards.
        let quadVertices: [QuadVertex] = [
            //              Positions                        TexCoords
            QuadVertex(position: float2(-1.0, -1.0), texCoord: float2(0.0, 1.0)),
            QuadVertex(position: float2(-1.0,  1.0), texCoord: float2(0.0, 0.0)),   // top left corner = origin of texture coord system
            QuadVertex(position: float2( 1.0, -1.0), texCoord: float2(1.0, 1.0)),
            QuadVertex(position: float2( 1.0,  1.0), texCoord: float2(1.0, 0.0))
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
        ///
        // Need another pipeline state to render a 1:1 quad offscreen.
        let equiRectVertexProgram = library.makeFunction(name: "projectTexture")
        // Load the fragment program into the library
        let equiRectFragmentProgram = library.makeFunction(name: "outputEquiRectangularTexture")
        quadPipelineDescriptor.label = "Offscreen PipelineState"
        quadPipelineDescriptor.vertexFunction = equiRectVertexProgram
        quadPipelineDescriptor.fragmentFunction = equiRectFragmentProgram
        quadPipelineDescriptor.depthAttachmentPixelFormat = .invalid
        // The geometry (of this 2x2 quad) is embedded in the vertex function.
        quadPipelineDescriptor.vertexDescriptor = nil
        do {
            try offscreenPipelineState = device.makeRenderPipelineState(descriptor: quadPipelineDescriptor)
        }
        catch let error {
            Swift.print("Failed to created offscreen pipeline state - error:", error)
        }

        // The ratio of the dimensions of the generated texture must be declared 2:1
        let texDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: view.colorPixelFormat,
                                                                     width: equiRectMapWidth, height: equiRectMapHeight,
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

    // Generate a 2D texture whose dimensions are 2:1.
    // This equirectangular texture is rendered offscreen.
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
            // Set the dimensions of the view port to equiRectMapWidth:equiRectMapHeight which is 2:1
            let viewPort = MTLViewport(originX: 0, originY: 0,
                                       width: Double(equiRectMapWidth), height: Double(equiRectMapHeight),
                                       znear: 0, zfar: 1)
            commandEncoder.setViewport(viewPort)
            commandEncoder.setFragmentTexture(cubeMapTexture,
                                              index: 0)
            // The geometry of the quad is embedded with the vertex function "projectTexture"
            commandEncoder.drawPrimitives(type: .triangle,
                                          vertexStart: 0,
                                          vertexCount: 6)

            commandEncoder.endEncoding()
            commandBuffer.commit()
            //commandBuffer.waitUntilCompleted()
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
            // The drawable's layer's pixelFormat is rgba16Float
            //Swift.print(drawable.layer.pixelFormat.rawValue)
            commandBuffer.label = "Drawable Texture"

            let renderQuadEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
            renderQuadEncoder.setRenderPipelineState(quadPipelineState)
            renderQuadEncoder.setFrontFacing(.clockwise)
            // Note: the geometry is a 1:1 quad but the output texture is 2:1.
            renderQuadEncoder.setVertexBuffer(quadBuffer,
                                              offset: 0,
                                              index: 0)
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
 
