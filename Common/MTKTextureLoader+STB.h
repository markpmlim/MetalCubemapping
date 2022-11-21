/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for common utility functions.
*/


#import <simd/simd.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#define STB_IMAGE_IMPLEMENTATION
#import "stb_image.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTKTextureLoader (STB)
/// As a source of HDR input, renderer leverages on radiance (.hdr) files.
/// This helper method returns an instance of MTLTexture given a source file name.
/// Will throw when called from Swift.

- (id<MTLTexture> _Nullable) newTextureFromRadianceFile:(NSString *_Nullable)fileName
                                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
