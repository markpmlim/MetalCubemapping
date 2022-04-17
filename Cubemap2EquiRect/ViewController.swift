//
//  ViewController.swift
//  Cubemap2EquiRect
//
//  Created by Mark Lim Pak Mun on 15/10/2020.
//  Copyright © 2020 Mark Lim Pak Mun. All rights reserved.
//

import Cocoa
import MetalKit
import AVFoundation

class ViewController: NSViewController {
    @IBOutlet var mtkView: MTKView!
    var renderer: Renderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        let device = MTLCreateSystemDefaultDevice()!
        mtkView.device = device
        mtkView.framebufferOnly = false
        // Configure
        mtkView.colorPixelFormat = .rgba16Float
        mtkView.depthStencilPixelFormat = .depth32Float
        renderer = Renderer(view: mtkView,
                            device: device)

        // The instruction below is necessary.
        mtkView.delegate = renderer

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

    func writeTexture(_ texture2D: MTLTexture,
                      with fileName: String,
                      at directoryURL: URL) {
        let name = fileName + ".hdr"
        let pixelFormat = texture2D.pixelFormat
        if (pixelFormat != .rgba16Float) {
            Swift.print("Wrong pixel format: can't save this file")
        }
        let url = directoryURL.appendingPathComponent(name)
        // Note: the pixel format of the mtl texture is rgba16Float.
        let options: [String : Any] = [
            String(kCIContextWorkingFormat) : NSNumber(value: kCIFormatRGBAh)
        ]
        var ciImage = CIImage(mtlTexture: texture2D,
                              options: options)!
        // We need to flip the image vertically and convert its
        //  the resolution of its dimensions from 1:1 to 2:1.
        var transform = CGAffineTransform(translationX: 0.0,
                                          y: ciImage.extent.height)
        transform = transform.scaledBy(x: 2.0, y: -1.0)
        ciImage = ciImage.transformed(by: transform)

        let cgImage = createCGImage(from: ciImage)

        var error: NSError?
        let ok = writeCGImage(cgImage!, url, &error)
        if !ok {
            Swift.print(error)
        }
    }

    // As soon as the view of the equirectangular map appears, pressing
    // "s" or "S" will allow the user to save it as a graphic.
    override func keyDown(with event: NSEvent) {
        let chars = event.characters
        let index0 = chars?.startIndex
        if chars![index0!] == "s" || chars![index0!] == "S" {
            guard let texture = renderer.equiRectangularTexture
            else {
                super.keyDown(with: event)
                return
            }
            let op = NSSavePanel()
            op.canCreateDirectories = true
            op.nameFieldStringValue = "image"
            let buttonID = op.runModal()
            if buttonID == NSApplication.ModalResponse.OK {
                let fileName = op.nameFieldStringValue
                let folderURL = op.directoryURL!
                writeTexture(texture,
                             with: fileName,
                             at: folderURL)
            }
        }
        else {
            super.keyDown(with: event)
        }
    }
}

