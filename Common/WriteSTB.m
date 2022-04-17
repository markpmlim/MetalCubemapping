/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of common utility functions.
*/

#import <ImageIO/ImageIO.h>
#import <Cocoa/Cocoa.h>
#import "AAPLMathUtilities.h"
#include "WriteSTB.h"




#pragma mark Texture Load

// --
// Modification of code from Apple's PostProcessingPipeline project

BOOL writeCGImage(CGImageRef cgImageRef, NSURL *url, NSError **error)
{
    // --------------
    // Validate input

    if (![url.absoluteString containsString:@"."])
    {
        if (error != NULL)
        {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"No file extension provided."}];
        }
        return NO;
    }

    NSArray * subStrings = [url.absoluteString componentsSeparatedByString:@"."];

    if ([subStrings[1] compare:@"hdr"] != NSOrderedSame)
    {
        if (error != NULL)
        {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"Only (.hdr) files are supported."}];
        }
        return NO;
    }

    //------------------------
    // Load and Validate Image

    const char *filePath = [url fileSystemRepresentation];
    //NSLog(@"%s", filePath);

    NSBitmapImageRep* bir = [[NSBitmapImageRep alloc] initWithCGImage:cgImageRef];
    //NSLog(@"%lu", (unsigned long)bir.bitmapFormat);
    uint16 *srcData = (uint16 *)bir.bitmapData;
    size_t width = bir.pixelsWide;
    size_t height = bir.pixelsHigh;
    //NSLog(@"%lu %lu", width, height);

    if (srcData == NULL)
    {
        if (error != NULL)
        {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"Unable to access raw image data."}];
        }
        return NO;
    }


    const size_t kSrcChannelCount = 4;
    const size_t kBitsPerByte = 8;
    const size_t kExpectedBitsPerPixel = sizeof(uint16_t) * kSrcChannelCount * kBitsPerByte;

    // source data is RGBA F16,
    const size_t kPixelCount = width * height;
    const size_t kDstChannelCount = 3;
    const size_t kDstSize = kPixelCount * sizeof(float) * kDstChannelCount;

    float * dstData = (float *)malloc(kDstSize);

    for (size_t pixelIdx = 0; pixelIdx < kPixelCount; ++pixelIdx)
    {
        const uint16_t * currSrc = srcData + (pixelIdx * kSrcChannelCount);
        float * currDst = dstData + (pixelIdx * kDstChannelCount);

        currDst[0] = float32_from_float16(currSrc[0]);
        currDst[1] = float32_from_float16(currSrc[1]);
        currDst[2] = float32_from_float16(currSrc[2]);
    }

    // kCIFormatRGBAf A 128-bit, floating point pixel format.
    int err = stbi_write_hdr(filePath,
                             (int)width, (int)height,
                             3,
                             dstData);
    // Remember to clean things up
    free(dstData);
    if (err == 0)
    {
        if (error != NULL)
        {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"Unable to write hdr file."}];
        }
        return NO;

    }
    return YES;
}

