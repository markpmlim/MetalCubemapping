#if os(macOS)
import AppKit
#else
import UIKit
#endif

// https://stackoverflow.com/questions/48872043/how-to-load-16-bit-images-into-metal-textures
func convertRGBF32ToRGBAF16(_ src: UnsafePointer<Float>,
                            _ dst: UnsafeMutablePointer<UInt16>,
                            pixelCount: Int) {

    for i in 0..<pixelCount {
        storeAsF16(src[i * 3 + 0], dst + (i * 4) + 0)
        storeAsF16(src[i * 3 + 1], dst + (i * 4) + 1)
        storeAsF16(src[i * 3 + 2], dst + (i * 4) + 2)
        storeAsF16(1.0,            dst + (i * 4) + 3)          // alpha=1.0
    }
}

// Doesn't work
// Assumed we are passed a 64-bit integer/pixel raw image, 16-bit integer/channel
// TIFF/PNG/JPEG 16-bit graphics: are these 16-bit integers?
func convertRGBA16ToRGBAF16(_ src: UnsafePointer<UInt16>,
                            _ dst: UnsafeMutablePointer<UInt16>,
                            pixelCount: Int) {
    
    var float16: Float = 0
    for i in 0..<pixelCount {
        float16 = Float(src[i * 4 + 0]/0xffff)
        storeAsF16(float16,  dst + (i * 4) + 0)
        float16 = Float(src[i * 4 + 1]/0xffff)
        storeAsF16(float16,  dst + (i * 4) + 1)
        float16 = Float(src[i * 4 + 2]/0xffff)
        storeAsF16(float16,  dst + (i * 4) + 2)
        float16 = Float(src[i * 4 + 3]/0xffff)
        storeAsF16(float16,   dst + (i * 4) + 3)
    }
}

/*
 The CGImageSource functions can load .HDR files as 32-bit RGB.
 */
func loadEXRTexture(_ url: URL,
                    device: MTLDevice) -> MTLTexture? {

    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
    else {
        return nil
    }

    let options = [ kCGImageSourceShouldCache : true, kCGImageSourceShouldAllowFloat : true ] as CFDictionary

    guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, options)
    else {
        return nil
    }

    // The image's width and height are expressed in pixels.
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                              width: image.width,
                                                              height: image.height,
                                                              mipmapped: false)
    descriptor.usage = .shaderRead
    guard let texture = device.makeTexture(descriptor: descriptor)
    else {
        return nil
    }

    // Note: the caller must check the following: bpc=32 & bbp=96
    if image.bitsPerComponent == 32 && image.bitsPerPixel == 96 {
        let srcData: CFData! = image.dataProvider?.data
        CFDataGetBytePtr(srcData).withMemoryRebound(to: Float.self,
                                                    capacity: image.width * image.height * 3) {
            srcPixels in
            let dstPixels = UnsafeMutablePointer<UInt16>.allocate(capacity: 4 * image.width * image.height)
            convertRGBF32ToRGBAF16(srcPixels,
                                   dstPixels,
                                   pixelCount: image.width * image.height)
            texture.replace(region: MTLRegionMake2D(0, 0, image.width, image.height),
                            mipmapLevel: 0,
                            withBytes: dstPixels,
                            bytesPerRow: MemoryLayout<UInt16>.size * 4 * image.width)
            dstPixels.deallocate()
        }
    }
    return texture
}

// Load a graphic file and return an instance of MTLTexture with a MTLPixelFormat of RGBA16Float
func loadTextureAsRGBA16Float(_ url: URL,
                              device: MTLDevice) -> MTLTexture? {

    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
    else {
        return nil
    }

    let options = [ kCGImageSourceShouldCache : true, kCGImageSourceShouldAllowFloat : true ] as CFDictionary

    guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, options)
    else {
        return nil
    }

    // The image's width and height are expressed in pixels.
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                                                              width: image.width,
                                                              height: image.height,
                                                              mipmapped: false)
    descriptor.usage = .shaderRead
    guard let texture = device.makeTexture(descriptor: descriptor)
    else {
        return nil
    }

    let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder16Little.rawValue |
                                             CGImageAlphaInfo.premultipliedLast.rawValue |
                                             CGBitmapInfo.floatComponents.rawValue))

    // Needs linearSRGB colorspace or colors appears 'washout'
    guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB)
    else {
        return nil
    }

    // Each pixel consists of 4 Half floats = 4 x 2 = 8 bytes.
    let bytesPerRow = image.width * 8
    let context = CGContext(data: nil,
                            width: texture.width,
                            height: texture.height,
                            bitsPerComponent: 16,
                            bytesPerRow: bytesPerRow,
                            space: colorSpace,
                            bitmapInfo: bitmapInfo.rawValue)
    let whichRect = CGRect(x: 0, y: 0,
                           width: CGFloat(image.width), height: CGFloat(image.height))
    context?.clear(whichRect)
    context?.draw(image, in: whichRect)
    context?.flush()
    let data = context!.data    // ptr to the raw bitmap

    let region = MTLRegionMake2D(0, 0,
                                 texture.width, texture.height)
    texture.replace(region: region,
                    mipmapLevel: 0,
                    withBytes: data!,
                    bytesPerRow: image.width * 8)
    return texture
}

// We assume each image has bpc=8 and bpp=32
func bitmapData(forImage cgImage: CGImage) -> UnsafeMutableRawPointer {
    let width = cgImage.width
    let height = cgImage.height
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    let bytesPerPixel = 4
    let bitsPerComponent = 8
    let rawData = malloc(height * width * bytesPerPixel)
    let bytesPerRow = bytesPerPixel * width
    let context = CGContext(data: rawData,
                            width: width, height: height,
                            bitsPerComponent: bitsPerComponent,
                            bytesPerRow: bytesPerRow,
                            space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue + CGBitmapInfo.byteOrder32Big.rawValue)
    let bounds = CGRect(x: 0, y: 0,
                         width: width, height: height)
    context!.clear(bounds)
    context!.draw(cgImage, in: bounds)
    return rawData!
}
