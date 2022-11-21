/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of common utility functions.
*/

#import "AAPLMathUtilities.h"

#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <Metal/Metal.h>
#import "MTKTextureLoader+STB.h"

#import <simd/simd.h>



#pragma mark Texture Load

// --
// Modification of code from Apple's PostProcessingPipeline project
// Returns an instance of MTLTexture with a texture type MTLTextureType.type2D
//  and a pixelFormat MTLPixelFormat.rgba16Float
@implementation MTKTextureLoader (STB)

- (id<MTLTexture>_Nullable) newTextureFromRadianceFile:(NSString *_Nullable)fileName
                                                 error:(NSError *__nullable *__nullable)error {

    // --------------
    // Validate input

    if (![fileName containsString:@"."]) {
        if (error != NULL) {
            *error = [[NSError alloc] initWithDomain:@"File load failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"No file extension provided."}];
        }
        return nil;
    }

    NSArray * subStrings = [fileName componentsSeparatedByString:@"."];

    if ([subStrings[1] compare:@"hdr"] != NSOrderedSame) {
        if (error != NULL) {
            *error = [[NSError alloc] initWithDomain:@"File load failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"Only (.hdr) files are supported."}];
        }
        return nil;
    }

    //------------------------
    // Load and Validate Image

    NSString* filePath = [[NSBundle mainBundle] pathForResource:subStrings[0]
                                                         ofType:subStrings[1]];

    int width, height, numOfChannels;

    // The HDR format has 3 channels R, G, B, each a 32-bit Float  => 96 bits/pixel.
    // rgba16Float has four channels R, G, B, A, each component is a 16-bit Float => 64 bits/pixel.
    // In MSL, rgba16Float is a half4 (4x2=8 bytes in size).
    float* srcData = stbi_loadf([filePath cStringUsingEncoding:NSASCIIStringEncoding],
                                &width, &height,
                                &numOfChannels,
                                4);

    if (srcData == NULL) {
        if (error != NULL) {
            *error = [[NSError alloc] initWithDomain:@"File load failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"Unable to load raw image data."}];
        }
        return nil;
    }


    // kSrcChannelCount must be set 4 because the parameter req_comp of
    //  the stbi_loadf C function was set to 4
    const size_t kSrcChannelCount = 4;
    const size_t kBitsPerByte = 8;
    const size_t kExpectedBitsPerPixel = sizeof(float) * kSrcChannelCount * kBitsPerByte;
    //printf("%lu\n", kExpectedBitsPerPixel);

    // Metal exposes an RGBA16Float format, but source data is RGBA F32,
    const size_t kPixelCount = width * height;
    const size_t kDstChannelCount = 4;
    const size_t kDstSize = kPixelCount * sizeof(uint16_t) * kDstChannelCount;

    uint16_t * dstData = (uint16_t *)malloc(kDstSize);

    for (size_t texIdx = 0; texIdx < kPixelCount; ++texIdx) {

        const float * currSrc = srcData + (texIdx * kSrcChannelCount);
        uint16_t * currDst = dstData + (texIdx * kDstChannelCount);

        currDst[0] = float16_from_float32(currSrc[0]);
        currDst[1] = float16_from_float32(currSrc[1]);
        currDst[2] = float16_from_float32(currSrc[2]);
        currDst[3] = float16_from_float32(currSrc[3]);  // was set to 1.0 by stbi_loadf
    }

    //------------------
    // Create MTLTexture

    MTLTextureDescriptor * texDesc = [MTLTextureDescriptor new];

    texDesc.pixelFormat = MTLPixelFormatRGBA16Float;
    texDesc.width = width;
    texDesc.height = height;

    id<MTLTexture> texture = [self.device newTextureWithDescriptor:texDesc];

    const NSUInteger kBytesPerRow = sizeof(uint16_t) * kDstChannelCount * width;

    MTLRegion region = { {0,0,0}, {width, height, 1} };

    [texture replaceRegion:region
               mipmapLevel:0
                 withBytes:dstData
               bytesPerRow:kBytesPerRow];

    // Remember to clean things up
    free(dstData);
    stbi_image_free(srcData);

    return texture;
}
@end
