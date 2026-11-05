#import "VCH264Decoder.h"
#import <VideoToolbox/VideoToolbox.h>
#include <string.h>

@implementation VCH264Decoder {
    VTDecompressionSessionRef _session;
    CMVideoFormatDescriptionRef _formatDesc;
    uint8_t *_savedSPS;
    size_t _savedSPSSize;
    uint8_t *_savedPPS;
    size_t _savedPPSSize;
}

static void decompressionCallback(void *decompressionOutputRefCon,
                                   void *sourceFrameRefCon,
                                   OSStatus status,
                                   VTDecodeInfoFlags flags,
                                   CVImageBufferRef imageBuffer,
                                   CMTime pts,
                                   CMTime duration) {
    if (status != noErr || !imageBuffer) return;
    VCH264Decoder *decoder = (__bridge VCH264Decoder *)decompressionOutputRefCon;
    if (!decoder.delegate) return;

    CMVideoFormatDescriptionRef fmt = NULL;
    CMSampleBufferRef sbuf = NULL;
    CMSampleTimingInfo timing = {duration, pts, kCMTimeInvalid};

    if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, &fmt) != noErr) return;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, imageBuffer, YES,
                                        NULL, NULL, fmt, &timing, &sbuf);
    CFRelease(fmt);
    if (!sbuf) return;

    [decoder.delegate outputFrame:(__bridge void *)sbuf
            presentationTimeStamp:pts.value
             presentationDuration:duration.value];
    CFRelease(sbuf);
}

- (BOOL)initDecoder:(const uint8_t *)spsData spsSize:(size_t)spsSize
                pps:(const uint8_t *)ppsData ppsSize:(size_t)ppsSize {
    [self endDecode];

    // Save SPS/PPS for reinit
    free(_savedSPS);
    _savedSPS = malloc(spsSize);
    memcpy(_savedSPS, spsData, spsSize);
    _savedSPSSize = spsSize;

    free(_savedPPS);
    _savedPPS = malloc(ppsSize);
    memcpy(_savedPPS, ppsData, ppsSize);
    _savedPPSSize = ppsSize;

    const uint8_t *paramSets[] = {spsData, ppsData};
    const size_t paramSizes[] = {spsSize, ppsSize};

    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
        kCFAllocatorDefault, 2, paramSets, paramSizes, 4, &_formatDesc);
    if (status != noErr) return NO;

    NSDictionary *attrs = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:
            @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };

    VTDecompressionOutputCallbackRecord callback = {
        .decompressionOutputCallback = decompressionCallback,
        .decompressionOutputRefCon = (__bridge void *)self,
    };

    status = VTDecompressionSessionCreate(kCFAllocatorDefault, _formatDesc,
                                           NULL, (__bridge CFDictionaryRef)attrs,
                                           &callback, &_session);
    return status == noErr;
}

- (void)decode:(const uint8_t *)data size:(size_t)size pts:(int32_t)pts {
    if (!_session || !data || size < 5) return;

    CMBlockBufferRef blockBuf = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault, (void *)data, size, kCFAllocatorNull,
        NULL, 0, size, 0, &blockBuf);
    if (status != noErr || !blockBuf) return;

    CMSampleBufferRef sbuf = NULL;
    const size_t sampleSize = size;
    CMSampleTimingInfo timing = {
        kCMTimeInvalid,
        CMTimeMake(pts, 1000),
        kCMTimeInvalid
    };
    status = CMSampleBufferCreateReady(kCFAllocatorDefault, blockBuf,
                                        _formatDesc, 1, 1, &timing,
                                        1, &sampleSize, &sbuf);
    CFRelease(blockBuf);
    if (status != noErr || !sbuf) return;

    VTDecodeFrameFlags decodeFlags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecompressionSessionDecodeFrame(_session, sbuf, decodeFlags, NULL, NULL);
    CFRelease(sbuf);
}

- (void)endDecode {
    if (_session) {
        VTDecompressionSessionWaitForAsynchronousFrames(_session);
        VTDecompressionSessionInvalidate(_session);
        CFRelease(_session);
        _session = NULL;
    }
    if (_formatDesc) {
        CFRelease(_formatDesc);
        _formatDesc = NULL;
    }
}

- (BOOL)reinitFromSaved {
    if (!_savedSPS || !_savedPPS) return NO;
    return [self initDecoder:_savedSPS spsSize:_savedSPSSize
                         pps:_savedPPS ppsSize:_savedPPSSize];
}

- (void)dealloc {
    [self endDecode];
    free(_savedSPS);
    free(_savedPPS);
}

@end
