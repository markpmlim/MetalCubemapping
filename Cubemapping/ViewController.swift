//
//  ViewController.swift
//  MetalCubemapping
//
//  Created by Mark Lim Pak Mun on 27/08/2020.
//  Copyright © 2020 Mark Lim Pak Mun. All rights reserved.
//

import Cocoa
import MetalKit

class ViewController: NSViewController {
    @IBOutlet var mtkView: MTKView!
    
    var renderer: CubemapRenderer!

    override func viewDidLoad() {
        super.viewDidLoad()
        // The view seems to have been instantiated w/o a "device" property.
        let device = MTLCreateSystemDefaultDevice()!
        mtkView.device = device
        // Configure
        mtkView.colorPixelFormat = .bgra8Unorm
        // A depth buffer is required
        mtkView.depthStencilPixelFormat = .depth32Float
        renderer = CubemapRenderer(view: mtkView,
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


}

