/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for common utility functions.
*/


#import <simd/simd.h>
#import <Foundation/Foundation.h>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#import "stb_image_write.h"


/// As a source of HDR output, renderer leverages radiance (.hdr) files.
///  This helper method output a radiance file
/// Supposed to throw when called from Swift.
BOOL writeCGImage(CGImageRef cgImageRef, NSURL *url, NSError **error);


