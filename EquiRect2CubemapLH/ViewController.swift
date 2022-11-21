//
//  ViewController.swift
//  EquiRect2CubemapLH
//
//  Created by Mark Lim Pak Mun on 07/60/2022.
//  Copyright © 2022 Mark Lim Pak Mun. All rights reserved.
//

import Cocoa
import MetalKit

@available(OSX 10.13.4, *)
class ViewController: NSViewController {
    @IBOutlet var mtkView: MTKView!

    var renderer: EquiRectagularRenderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        // The view seems to have been instantiated w/o a "device" property.
        let device = MTLCreateSystemDefaultDevice()!
        mtkView.device = device
        // Configure
        mtkView.colorPixelFormat = .rgba16Float
        // A depth buffer is required
        mtkView.depthStencilPixelFormat = .depth32Float
        renderer = EquiRectagularRenderer(view: mtkView,
                                          device: device)
        mtkView.delegate = renderer     // this is necessary.

        let size = mtkView.drawableSize
        // Ensure the view and projection matrices are setup
        renderer.mtkView(mtkView,
                         drawableSizeWillChange: size)
    }

    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }

    override func viewDidAppear() {
        self.mtkView.window!.makeFirstResponder(self)
    }

    func createCGImage(from ciImage: CIImage) -> CGImage? {
        let ciContext = CIContext(mtlDevice: mtkView.device!)
        let cgRect = ciImage.extent
        let cgImage = ciContext.createCGImage(ciImage,
                                              from: cgRect,
                                              format: kCIFormatRGBAh,
                                              colorSpace: CGColorSpaceCreateDeviceRGB())
        return cgImage
    }

    func writeTexture(_ cubeMapTexture: MTLTexture,
                      with baseName: String,
                      at directoryURL: URL) {
        for i in 0..<6 {
            let fileName = baseName + String(i) + ".hdr"
            let url = directoryURL.appendingPathComponent(fileName)
            //let rangeOfSlices = i..<(i+1)
            let rangeOfSlices = Range(i..<(i+1))
            let faceTexture = cubeMapTexture.makeTextureView(pixelFormat: cubeMapTexture.pixelFormat,
                                                             textureType: MTLTextureType.type2D,
                                                             levels: 0..<1,
                                                             slices: rangeOfSlices)!
            // Note: the pixel format of the MTL texture is rgba16Float (64 bits)
            // The default for GPU rendering is kCIFormatRGBAf (128 bits)
            let options: [String : Any] = [
                String(kCIContextWorkingFormat) : NSNumber(value: kCIFormatRGBAh)
            ]
            var ciImage = CIImage(mtlTexture: faceTexture,
                                  options: options)!
            // We need to flip the image vertically.
            var transform = CGAffineTransform(translationX: 0.0,
                                              y: ciImage.extent.height)
            transform = transform.scaledBy(x: 1.0, y: -1.0)
            ciImage = ciImage.transformed(by: transform)

            let cgImage = createCGImage(from: ciImage)
            var error: NSError? = nil
            // writeCGImage is just a plain C function.
            let ok = writeCGImage(cgImage!, url, &error)
            if !ok {
                // KIV. Put up an alert here
                Swift.print(error! as NSError)
            }
        } // for
    }
    
    // To save the generated cubemap faces, the user must wait
    // for the view to appear displaying the background environment map
    // before pressing an "s" or "S" key.
    override func keyDown(with event: NSEvent) {
        let chars = event.characters
        let index0 = chars?.startIndex
        if chars![index0!] == "s" || chars![index0!] == "S" {
            guard let cubeMapTexture = renderer.cubeMapTexture
            else {
                super.keyDown(with: event)
                return
            }
            let op = NSSavePanel()
            op.canCreateDirectories = true
            op.nameFieldStringValue = "image"
            let buttonID = op.runModal()
            if buttonID == NSApplication.ModalResponse.OK {
                let baseName = op.nameFieldStringValue
                let folderURL = op.directoryURL!
                writeTexture(cubeMapTexture,
                             with: baseName,
                             at: folderURL)
            }
        }
        else {
            super.keyDown(with: event)
        }
    }

}


