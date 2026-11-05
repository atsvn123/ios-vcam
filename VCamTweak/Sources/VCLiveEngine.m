#import "VCLiveEngine.h"
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>
#include <string.h>
#include <math.h>
#include <QuartzCore/QuartzCore.h>

static VCLiveEngine *s_sharedEngine = nil;

static BOOL vcam_fill_black(CVPixelBufferRef buffer) {
    if (!buffer || CVPixelBufferLockBaseAddress(buffer, 0) != kCVReturnSuccess) return NO;
    OSType format = CVPixelBufferGetPixelFormatType(buffer);
    BOOL filled = YES;
    if ((format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
         format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) &&
        CVPixelBufferIsPlanar(buffer) && CVPixelBufferGetPlaneCount(buffer) == 2) {
        for (size_t plane = 0; plane < 2; plane++) {
            void *base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane);
            size_t bytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) *
                           CVPixelBufferGetHeightOfPlane(buffer, plane);
            int fill = (format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange && plane == 0)
                ? 16 : ((plane == 0) ? 0 : 0x80);
            if (base) memset(base, fill, bytes);
            else filled = NO;
        }
    } else if (!CVPixelBufferIsPlanar(buffer)) {
        uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
        size_t stride = CVPixelBufferGetBytesPerRow(buffer);
        size_t height = CVPixelBufferGetHeight(buffer);
        size_t width = CVPixelBufferGetWidth(buffer);
        BOOL rgb = format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32RGBA ||
                   format == kCVPixelFormatType_32ARGB || format == kCVPixelFormatType_32ABGR;
        if (!base || !rgb) {
            filled = NO;
        } else {
            memset(base, 0, stride * height);
            size_t alpha = (format == kCVPixelFormatType_32BGRA ||
                            format == kCVPixelFormatType_32RGBA) ? 3 : 0;
            for (size_t y = 0; y < height; y++) {
                uint8_t *row = base + y * stride;
                for (size_t x = 0; x < width; x++) row[x * 4 + alpha] = 255;
            }
        }
    } else {
        filled = NO;
    }
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    return filled;
}

@implementation VCLiveEngine {
    NSRecursiveLock *_lock;
    BOOL _userIntentLive;
    int _mediaType;          // 0=RTMP, 1=Image, 2=Video
    int _mediaFitMode;       // 0=Letterbox, 1=Trim
    int _performanceFPS;
    int _videoDetectedRotation;
    NSUInteger _mediaImageGeneration;
    CFAbsoluteTime _lastSourceFrameUpdate;
    CFTimeInterval _lastSourceFrameReceived;
    NSString *_mediaPath;
    CMSampleBufferRef _liveYUVSampleBuffer;
    AVAssetReader *_videoReader;
    AVAssetReaderTrackOutput *_videoTrackOutput;
    dispatch_queue_t _mediaQueue;
    VTPixelTransferSessionRef _rtmpTransferSession;
    VTPixelTransferSessionRef _mediaTransferSession;
    CFTimeInterval _lastInjectionReset;
    BOOL _mediaLoop;
    int _videoReaderRetryCount;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_sharedEngine = [[VCLiveEngine alloc] init];
    });
    return s_sharedEngine;
}

+ (instancetype)existingInstance {
    return s_sharedEngine;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _bLive = NO;
        _cameraTarget = 0;
        _lock = [NSRecursiveLock new];
        _mediaType = 0;
        _mediaFitMode = 0;
        _performanceFPS = 0;
        _mediaLoop = YES;
        _videoDetectedRotation = -1;
        _mediaQueue = dispatch_queue_create("com.vcam.media", DISPATCH_QUEUE_SERIAL);

        [self setupTransferSession:&_rtmpTransferSession trim:YES];
        [self setupTransferSession:&_mediaTransferSession trim:NO];
    }
    return self;
}

- (void)setupTransferSession:(VTPixelTransferSessionRef *)session trim:(BOOL)trim {
    VTPixelTransferSessionCreate(kCFAllocatorDefault, session);
    VTSessionSetProperty((VTSessionRef)*session,
                         kVTPixelTransferPropertyKey_DestinationColorPrimaries,
                         kCVImageBufferColorPrimaries_ITU_R_709_2);
    VTSessionSetProperty((VTSessionRef)*session,
                         kVTPixelTransferPropertyKey_DestinationTransferFunction,
                         kCVImageBufferTransferFunction_ITU_R_709_2);
    VTSessionSetProperty((VTSessionRef)*session,
                         kVTPixelTransferPropertyKey_DestinationYCbCrMatrix,
                         kCVImageBufferYCbCrMatrix_ITU_R_601_4);
    VTSessionSetProperty((VTSessionRef)*session,
                         kVTPixelTransferPropertyKey_ScalingMode,
                         trim ? kVTScalingMode_Trim : CFSTR("Letterbox"));
    VTSessionSetProperty((VTSessionRef)*session,
                         kVTPixelTransferPropertyKey_EnableGPUAcceleratedTransfer,
                         kCFBooleanTrue);
}

- (void)resetTransferSession:(BOOL)isRTMP {
    VTPixelTransferSessionRef *slot = isRTMP ? &_rtmpTransferSession : &_mediaTransferSession;
    if (*slot) {
        VTPixelTransferSessionInvalidate(*slot);
        CFRelease(*slot);
        *slot = NULL;
    }
    BOOL trim = isRTMP || _mediaFitMode == 1;
    [self setupTransferSession:slot trim:trim];
}

- (BOOL)shouldInjectForCameraPosition:(int)position {
    int target = self.cameraTarget;
    return target == 0 || (position != 0 && position == target);
}

- (BOOL)blackoutImageBuffer:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = sampleBuffer ? CMSampleBufferGetImageBuffer(sampleBuffer) : NULL;
    return imageBuffer ? vcam_fill_black((CVPixelBufferRef)imageBuffer) : NO;
}

- (BOOL)getLive {
    [_lock lock];
    BOOL live = _bLive || _userIntentLive;
    [_lock unlock];
    return live;
}

- (void)setLive:(BOOL)live {
    _bLive = live;
}

- (void)setLiveUserIntent:(BOOL)intent {
    [_lock lock];
    _userIntentLive = intent;
    [_lock unlock];
    if (!intent) {
        _bLive = NO;
        [_lock lock];
        if (_liveYUVSampleBuffer) {
            CFRelease(_liveYUVSampleBuffer);
            _liveYUVSampleBuffer = NULL;
        }
        [_lock unlock];
        [self stopVideoReader];
    } else {
        [_lock lock];
        BOOL readerUnavailable = (!_videoReader ||
                                  _videoReader.status != AVAssetReaderStatusReading);
        NSString *path = (_mediaType == 2 && readerUnavailable && _mediaPath.length > 0)
            ? [_mediaPath copy] : nil;
        NSUInteger generation = _mediaImageGeneration;
        [_lock unlock];
        if (path) {
            dispatch_async(_mediaQueue, ^{
                if (generation == self->_mediaImageGeneration && self->_userIntentLive &&
                    self->_mediaType == 2 && (!self->_videoReader ||
                    self->_videoReader.status != AVAssetReaderStatusReading) &&
                    [self->_mediaPath isEqualToString:path]) {
                    [self stopVideoReader];
                    [self startVideoReader:path];
                }
            });
        }
    }
}

// RTMP frame input — only accept when mediaType==0
- (void)setYUVSampleBuffer:(CMSampleBufferRef)sbuf {
    if (!sbuf) return;
    [_lock lock];
    if (_mediaType != 0) { [_lock unlock]; return; }
    _lastSourceFrameReceived = CACurrentMediaTime();

    int fps = _performanceFPS;
    CFAbsoluteTime lastUpdate = _lastSourceFrameUpdate;
    CFAbsoluteTime now = CACurrentMediaTime();
    BOOL shouldDrop = fps > 0 && lastUpdate > 0 && now + 0.001 < lastUpdate;
    if (!shouldDrop && fps > 0) {
        CFTimeInterval period = 1.0 / (CFTimeInterval)fps;
        _lastSourceFrameUpdate = (lastUpdate > 0 && now - lastUpdate < period)
            ? lastUpdate + period : now + period;
    }
    if (shouldDrop) { [_lock unlock]; return; }

    CMSampleBufferRef replacement = (CMSampleBufferRef)CFRetain(sbuf);
    if (_liveYUVSampleBuffer) CFRelease(_liveYUVSampleBuffer);
    _liveYUVSampleBuffer = replacement;
    [_lock unlock];

    if (_userIntentLive && !_bLive) _bLive = YES;
}

// Frame injection — called from BWNodeOutput hook
- (CMSampleBufferRef)modifyImageBuffer:(CMSampleBufferRef)sampleBuffer {
    @autoreleasepool {
        if (!_bLive && !_userIntentLive) return nil;

        CVImageBufferRef destBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!destBuffer) return nil;

        [_lock lock];

        if (_userIntentLive && !_bLive) _bLive = YES;
        if (!_bLive) {
            [_lock unlock];
            return nil;
        }
        if (!_liveYUVSampleBuffer) {
            vcam_fill_black((CVPixelBufferRef)destBuffer);
            [_lock unlock];
            return sampleBuffer;
        }

        // RTMP timeout — black out if no frames for >1s
        if (_mediaType == 0 && _lastSourceFrameReceived > 0.0 &&
            CACurrentMediaTime() - _lastSourceFrameReceived > 1.0) {
            vcam_fill_black((CVPixelBufferRef)destBuffer);
            [_lock unlock];
            return sampleBuffer;
        }

        CVImageBufferRef srcBuffer = CMSampleBufferGetImageBuffer(_liveYUVSampleBuffer);
        if (!srcBuffer) {
            vcam_fill_black((CVPixelBufferRef)destBuffer);
            [_lock unlock];
            return sampleBuffer;
        }

        VTPixelTransferSessionRef session = (_mediaType == 1 || _mediaType == 2)
            ? _mediaTransferSession : _rtmpTransferSession;

        OSStatus status = session
            ? VTPixelTransferSessionTransferImage(session, srcBuffer, (CVPixelBufferRef)destBuffer)
            : kCVReturnError;

        if (status != noErr) {
            CFTimeInterval now = CACurrentMediaTime();
            if (now - _lastInjectionReset >= 1.0) {
                _lastInjectionReset = now;
                [self resetTransferSession:(_mediaType == 0)];
                session = (_mediaType == 0) ? _rtmpTransferSession : _mediaTransferSession;
                if (session) {
                    status = VTPixelTransferSessionTransferImage(
                        session, srcBuffer, (CVPixelBufferRef)destBuffer);
                }
            }
        }

        [_lock unlock];

        if (status == noErr) {
            CVPixelBufferFillExtendedPixels((CVPixelBufferRef)destBuffer);
            return sampleBuffer;
        }

        vcam_fill_black((CVPixelBufferRef)destBuffer);
        return nil;
    }
}

// Media source type
- (void)setMediaType:(int)type {
    if (type < 0 || type > 2) return;
    [_lock lock];
    _mediaType = type;
    _mediaImageGeneration++;
    if (_liveYUVSampleBuffer) {
        CFRelease(_liveYUVSampleBuffer);
        _liveYUVSampleBuffer = NULL;
    }
    NSString *path = [_mediaPath copy];
    NSUInteger generation = _mediaImageGeneration;
    if (type != 2) _videoDetectedRotation = -1;
    [_lock unlock];

    [self stopVideoReader];
    if (type == 1 && path.length > 0) {
        [self loadImageFile:path];
    } else if (type == 2 && path.length > 0) {
        dispatch_async(_mediaQueue, ^{
            if (generation == self->_mediaImageGeneration && self->_userIntentLive &&
                self->_mediaType == 2 && [self->_mediaPath isEqualToString:path]) {
                self->_videoReaderRetryCount = 0;
                [self startVideoReader:path];
            }
        });
    }
}

- (void)setMediaPath:(NSString *)path {
    NSString *newPath = [path copy];
    [_lock lock];
    BOOL changed = ![_mediaPath isEqualToString:newPath];
    _mediaPath = newPath;
    if (changed) {
        _mediaImageGeneration++;
        if (_liveYUVSampleBuffer) {
            CFRelease(_liveYUVSampleBuffer);
            _liveYUVSampleBuffer = NULL;
        }
    }
    int type = _mediaType;
    NSUInteger gen = _mediaImageGeneration;
    [_lock unlock];

    if (!changed) return;
    if (type == 1) {
        [self loadImageFile:newPath];
    } else if (type == 2) {
        [self stopVideoReader];
        dispatch_async(_mediaQueue, ^{
            if (gen == self->_mediaImageGeneration && self->_userIntentLive &&
                self->_mediaType == 2 && [self->_mediaPath isEqualToString:newPath]) {
                self->_videoReaderRetryCount = 0;
                [self startVideoReader:newPath];
            }
        });
    }
}

- (void)setMediaFitMode:(int)mode {
    if (mode < 0 || mode > 1) return;
    [_lock lock];
    if (_mediaFitMode == mode) { [_lock unlock]; return; }
    _mediaFitMode = mode;
    CFStringRef scalingMode = (mode == 1) ? CFSTR("Trim") : CFSTR("Letterbox");
    VTSessionSetProperty((VTSessionRef)_mediaTransferSession,
                         kVTPixelTransferPropertyKey_ScalingMode, scalingMode);
    [_lock unlock];
}

- (void)setPerformanceFPS:(int)fps {
    if (fps < 0) fps = 0;
    if (fps > 60) fps = 60;
    [_lock lock];
    _performanceFPS = fps;
    _lastSourceFrameUpdate = 0;
    [_lock unlock];
}

// Image loading — decode to BGRA CVPixelBuffer, wrap in CMSampleBuffer
- (void)loadImageFile:(NSString *)path {
    if (!path) return;
    [_lock lock];
    NSUInteger generation = _mediaImageGeneration;
    [_lock unlock];

    dispatch_async(_mediaQueue, ^{
      @autoreleasepool {
        [self->_lock lock];
        BOOL current = (generation == self->_mediaImageGeneration &&
                        [self->_mediaPath isEqualToString:path]);
        [self->_lock unlock];
        if (!current) return;

        NSData *imgData = [NSData dataWithContentsOfFile:path];
        if (!imgData) return;

        CGImageSourceRef imgSource = CGImageSourceCreateWithData((__bridge CFDataRef)imgData, NULL);
        if (!imgSource) return;

        NSDictionary *thumbOpts = @{
            (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
            (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @1280,
        };
        CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(
            imgSource, 0, (__bridge CFDictionaryRef)thumbOpts);
        CFRelease(imgSource);
        if (!cgImage) return;

        size_t w = CGImageGetWidth(cgImage);
        size_t h = CGImageGetHeight(cgImage);

        NSDictionary *attrs = @{
            (__bridge NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (__bridge NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
            (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        };
        CVPixelBufferRef pixbuf = NULL;
        if (CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                (__bridge CFDictionaryRef)attrs, &pixbuf) != kCVReturnSuccess) {
            CGImageRelease(cgImage);
            return;
        }
        CVPixelBufferLockBaseAddress(pixbuf, 0);
        void *baseAddr = CVPixelBufferGetBaseAddress(pixbuf);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixbuf);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(baseAddr, w, h, 8, bytesPerRow, cs,
            kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        CGContextTranslateCTM(ctx, 0, (CGFloat)h);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
        CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cgImage);
        CGContextRelease(ctx);
        CGColorSpaceRelease(cs);
        CVPixelBufferUnlockBaseAddress(pixbuf, 0);

        CMVideoFormatDescriptionRef fmt = NULL;
        CMSampleBufferRef sbuf = NULL;
        CMSampleTimingInfo timing = {kCMTimeInvalid, CMTimeMake(0, 600), kCMTimeInvalid};
        if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixbuf, &fmt) == noErr && fmt) {
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixbuf, YES,
                                               NULL, NULL, fmt, &timing, &sbuf);
        }
        if (sbuf) {
            [self->_lock lock];
            BOOL stillCurrent = (generation == self->_mediaImageGeneration &&
                                 self->_mediaType == 1 &&
                                 [self->_mediaPath isEqualToString:path]);
            if (stillCurrent) {
                if (self->_liveYUVSampleBuffer) CFRelease(self->_liveYUVSampleBuffer);
                self->_liveYUVSampleBuffer = (CMSampleBufferRef)CFRetain(sbuf);
            }
            [self->_lock unlock];
            CFRelease(sbuf);
        }
        if (fmt) CFRelease(fmt);
        CGImageRelease(cgImage);
        CVPixelBufferRelease(pixbuf);
      }
    });
}

// Video file reading — AVAssetReader with wall-clock pacing
- (void)startVideoReader:(NSString *)path {
  @autoreleasepool {
    if (!path) return;
    [_lock lock];
    NSUInteger sourceGeneration = _mediaImageGeneration;
    BOOL selected = (_userIntentLive && _mediaType == 2 && [_mediaPath isEqualToString:path]);
    [_lock unlock];
    if (!selected) return;

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL
                                            options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @YES}];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{
        dispatch_semaphore_signal(sema);
    }];
    if (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0) return;

    NSError *err = nil;
    if ([asset statusOfValueForKey:@"tracks" error:&err] != AVKeyValueStatusLoaded) return;

    AVAssetTrack *videoTrack = nil;
    for (AVAssetTrack *t in [asset tracksWithMediaType:AVMediaTypeVideo]) {
        videoTrack = t; break;
    }
    if (!videoTrack) return;

    // Detect rotation from preferredTransform
    CGAffineTransform transform = videoTrack.preferredTransform;
    CGFloat angle = atan2(transform.b, transform.a) * 180.0 / M_PI;
    if (angle < 0.0) angle += 360.0;
    int detectedRotation = -1;
    if (fabs(angle - 90.0) < 10.0) detectedRotation = 90;
    else if (fabs(angle - 180.0) < 10.0) detectedRotation = 180;
    else if (fabs(angle - 270.0) < 10.0) detectedRotation = 270;
    else if (fabs(angle) < 10.0 || fabs(angle - 360.0) < 10.0) detectedRotation = 0;

    NSDictionary *settings = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:
            @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    AVAssetReaderTrackOutput *output =
        [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:settings];
    output.alwaysCopiesSampleData = NO;

    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:nil];
    if (!reader || ![reader canAddOutput:output]) return;
    [reader addOutput:output];
    if (![reader startReading]) return;

    [_lock lock];
    if (sourceGeneration != _mediaImageGeneration || !_userIntentLive ||
        _mediaType != 2 || ![_mediaPath isEqualToString:path] || _videoReader) {
        [_lock unlock];
        [reader cancelReading];
        return;
    }
    _videoDetectedRotation = detectedRotation;
    _videoReader = reader;
    _videoTrackOutput = output;
    _lastSourceFrameUpdate = 0;
    [_lock unlock];

    // Read frames with wall-clock pacing
    CMTime firstPTS = kCMTimeInvalid;
    CFTimeInterval playbackStart = 0.0;

    while (reader.status == AVAssetReaderStatusReading) {
      @autoreleasepool {
        [_lock lock];
        BOOL stillReader = (_userIntentLive && _mediaType == 2 &&
                            [_mediaPath isEqualToString:path] && _videoReader == reader);
        [_lock unlock];
        if (!stillReader) break;

        CMSampleBufferRef sbuf = [output copyNextSampleBuffer];
        if (!sbuf) break;

        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sbuf);

        // Wall-clock pacing against monotonic clock
        if (CMTIME_IS_VALID(pts)) {
            if (!CMTIME_IS_VALID(firstPTS)) {
                firstPTS = pts;
                playbackStart = CACurrentMediaTime();
            } else {
                Float64 target = CMTimeGetSeconds(CMTimeSubtract(pts, firstPTS));
                Float64 elapsed = CACurrentMediaTime() - playbackStart;
                Float64 wait = target - elapsed;
                while (wait > 0.001) {
                    [_lock lock];
                    BOOL interrupted = _videoReader != reader || !_userIntentLive;
                    [_lock unlock];
                    if (interrupted) break;
                    usleep((useconds_t)llround(fmin(wait, 0.02) * 1000000.0));
                    wait = target - (CACurrentMediaTime() - playbackStart);
                }
            }
        } else {
            usleep(15000);
        }

        // Publish frame (with optional FPS throttle for video)
        [_lock lock];
        BOOL stillCurrent = (_userIntentLive && _mediaType == 2 &&
                             _videoReader == reader && [_mediaPath isEqualToString:path]);
        if (stillCurrent && _performanceFPS > 0) {
            CFTimeInterval targetPeriod = 1.0 / (CFTimeInterval)_performanceFPS;
            CFTimeInterval now = CACurrentMediaTime();
            if (_lastSourceFrameUpdate > 0 && (now - _lastSourceFrameUpdate) < targetPeriod * 0.85) {
                stillCurrent = NO;
            } else {
                _lastSourceFrameUpdate = now;
            }
        }
        if (stillCurrent) {
            CMSampleBufferRef replacement = (CMSampleBufferRef)CFRetain(sbuf);
            if (_liveYUVSampleBuffer) CFRelease(_liveYUVSampleBuffer);
            _liveYUVSampleBuffer = replacement;
        }
        [_lock unlock];
        CFRelease(sbuf);
      }
    }

    AVAssetReaderStatus finalStatus = reader.status;
    [_lock lock];
    BOOL ownsReader = (_videoReader == reader);
    if (ownsReader) {
        _videoReader = nil;
        _videoTrackOutput = nil;
    }
    [_lock unlock];
    if (!ownsReader && reader.status == AVAssetReaderStatusReading) {
        [reader cancelReading];
    }

    // Loop if configured
    if (ownsReader && finalStatus == AVAssetReaderStatusCompleted) {
        NSUInteger loopGen = _mediaImageGeneration;
        if (_userIntentLive && _mediaLoop && _mediaType == 2 &&
            [_mediaPath isEqualToString:path]) {
            NSString *loopPath = [path copy];
            dispatch_async(_mediaQueue, ^{
                if (loopGen != self->_mediaImageGeneration || !self->_userIntentLive ||
                    self->_mediaType != 2 || ![self->_mediaPath isEqualToString:loopPath]) return;
                [self startVideoReader:loopPath];
            });
        }
    } else if (ownsReader) {
        // Retry on error (up to 3 times)
        [_lock lock];
        BOOL shouldRetry = (_userIntentLive && _mediaType == 2 &&
                            _videoReaderRetryCount < 3 && [_mediaPath isEqualToString:path]);
        if (shouldRetry) _videoReaderRetryCount++;
        [_lock unlock];
        if (shouldRetry) {
            NSString *retryPath = [path copy];
            NSUInteger retryGen = _mediaImageGeneration;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                           _mediaQueue, ^{
                [self->_lock lock];
                BOOL retryCurrent = (retryGen == self->_mediaImageGeneration &&
                                     self->_userIntentLive && self->_mediaType == 2 &&
                                     [self->_mediaPath isEqualToString:retryPath]);
                [self->_lock unlock];
                if (retryCurrent) {
                    [self stopVideoReader];
                    [self startVideoReader:retryPath];
                }
            });
        }
    }
  }
}

- (void)stopVideoReader {
    [_lock lock];
    AVAssetReader *reader = _videoReader;
    _videoReader = nil;
    _videoTrackOutput = nil;
    [_lock unlock];
    if (reader && reader.status == AVAssetReaderStatusReading) {
        [reader cancelReading];
    }
}

@end
