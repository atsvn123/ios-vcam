#import "VCLiveEngine.h"
#import <ImageIO/ImageIO.h>
#import <CoreImage/CoreImage.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#import <QuartzCore/QuartzCore.h>

static VCLiveEngine *s_sharedEngine = nil;

static void vcam_copy_color_attachments(CVPixelBufferRef src, CVPixelBufferRef dst) {
    if (!src || !dst) return;
    CFStringRef keys[] = {
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferTransferFunctionKey,
        kCVImageBufferYCbCrMatrixKey,
    };
    for (int i = 0; i < 3; i++) {
        CFTypeRef val = CVBufferCopyAttachment(src, keys[i], NULL);
        if (val) {
            CVBufferSetAttachment(dst, keys[i], val, kCVAttachmentMode_ShouldPropagate);
            CFRelease(val);
        }
    }
}

static BOOL vcam_fill_black_pixel_buffer(CVPixelBufferRef buffer) {
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
    int _mediaType;           // 0=RTMP, 1=Image, 2=Video
    int _mediaFitMode;        // 0=Letterbox, 1=Trim
    int _performanceFPS;
    int _videoDetectedRotation;
    int _rtmpRotation;        // -1=Auto, 0=none, 90/180/270
    int _mediaRotation;       // -1=Auto, 0/90/180/270 explicit
    BOOL _rotationDirty;
    NSUInteger _mediaImageGeneration;
    NSUInteger _sourceFrameGeneration;
    CFAbsoluteTime _lastSourceFrameUpdate;
    CFTimeInterval _lastSourceFrameReceived;
    CFTimeInterval _lastInjectionReset;
    NSString *_mediaPath;
    CMSampleBufferRef _liveYUVSampleBuffer;
    CVPixelBufferRef _pixelYUVBuffer90;
    AVAssetReader *_videoReader;
    AVAssetReaderTrackOutput *_videoTrackOutput;
    dispatch_queue_t _mediaQueue;
    VTPixelTransferSessionRef _pixelTransferSession;
    VTPixelTransferSessionRef _mediaTransferSession;
    VTImageRotationSessionRef _imageRotationSession;    // 90
    VTImageRotationSessionRef _imageRotationSession180; // 180
    VTImageRotationSessionRef _imageRotationSession270; // 270
    BOOL _mediaLoop;
    BOOL _mediaPaused;
    int _videoReaderRetryCount;
    CGImageRef _normalizedImage;
    NSString *_normalizedImagePath;
    CIContext *_mediaCIContext;
}

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ s_sharedEngine = [[VCLiveEngine alloc] init]; });
    return s_sharedEngine;
}

+ (instancetype)existingInstance { return s_sharedEngine; }

- (void)vcam_resetInjectionSession {
    VTPixelTransferSessionRef *slot = (_mediaType == 0)
        ? &_pixelTransferSession : &_mediaTransferSession;
    if (*slot) {
        VTPixelTransferSessionInvalidate(*slot);
        CFRelease(*slot);
        *slot = NULL;
    }
    if (VTPixelTransferSessionCreate(kCFAllocatorDefault, slot) != noErr || !*slot) return;
    VTSessionSetProperty((VTSessionRef)*slot,
                         kVTPixelTransferPropertyKey_DestinationColorPrimaries,
                         kCVImageBufferColorPrimaries_ITU_R_709_2);
    VTSessionSetProperty((VTSessionRef)*slot,
                         kVTPixelTransferPropertyKey_DestinationTransferFunction,
                         kCVImageBufferTransferFunction_ITU_R_709_2);
    VTSessionSetProperty((VTSessionRef)*slot,
                         kVTPixelTransferPropertyKey_DestinationYCbCrMatrix,
                         kCVImageBufferYCbCrMatrix_ITU_R_601_4);
    VTSessionSetProperty((VTSessionRef)*slot, kVTPixelTransferPropertyKey_ScalingMode,
        (_mediaType == 0 || _mediaFitMode == 1) ? kVTScalingMode_Trim : CFSTR("Letterbox"));
    VTSessionSetProperty((VTSessionRef)*slot,
        kVTPixelTransferPropertyKey_EnableGPUAcceleratedTransfer, kCFBooleanTrue);
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.bLive = NO;
        self.cameraTarget = 0;

        _lock = [[NSRecursiveLock alloc] init];

        VTPixelTransferSessionCreate(kCFAllocatorDefault, &_pixelTransferSession);
        VTSessionSetProperty((VTSessionRef)_pixelTransferSession,
                             kVTPixelTransferPropertyKey_DestinationColorPrimaries,
                             kCVImageBufferColorPrimaries_ITU_R_709_2);
        VTSessionSetProperty((VTSessionRef)_pixelTransferSession,
                             kVTPixelTransferPropertyKey_DestinationTransferFunction,
                             kCVImageBufferTransferFunction_ITU_R_709_2);
        VTSessionSetProperty((VTSessionRef)_pixelTransferSession,
                             kVTPixelTransferPropertyKey_DestinationYCbCrMatrix,
                             kCVImageBufferYCbCrMatrix_ITU_R_601_4);
        VTSessionSetProperty((VTSessionRef)_pixelTransferSession,
                             kVTPixelTransferPropertyKey_ScalingMode,
                             kVTScalingMode_Trim);
        VTSessionSetProperty((VTSessionRef)_pixelTransferSession,
                             kVTPixelTransferPropertyKey_EnableGPUAcceleratedTransfer,
                             kCFBooleanTrue);

        VTPixelTransferSessionCreate(kCFAllocatorDefault, &_mediaTransferSession);
        VTSessionSetProperty((VTSessionRef)_mediaTransferSession,
                             kVTPixelTransferPropertyKey_DestinationColorPrimaries,
                             kCVImageBufferColorPrimaries_ITU_R_709_2);
        VTSessionSetProperty((VTSessionRef)_mediaTransferSession,
                             kVTPixelTransferPropertyKey_DestinationTransferFunction,
                             kCVImageBufferTransferFunction_ITU_R_709_2);
        VTSessionSetProperty((VTSessionRef)_mediaTransferSession,
                             kVTPixelTransferPropertyKey_DestinationYCbCrMatrix,
                             kCVImageBufferYCbCrMatrix_ITU_R_601_4);
        VTSessionSetProperty((VTSessionRef)_mediaTransferSession,
                             kVTPixelTransferPropertyKey_ScalingMode,
                             CFSTR("Letterbox"));
        VTSessionSetProperty((VTSessionRef)_mediaTransferSession,
                             kVTPixelTransferPropertyKey_EnableGPUAcceleratedTransfer,
                             kCFBooleanTrue);

        VTImageRotationSessionCreate(kCFAllocatorDefault, 90, &_imageRotationSession);
        VTSessionSetProperty((VTSessionRef)_imageRotationSession,
                             kVTImageRotationPropertyKey_EnableHighSpeedTransfer,
                             kCFBooleanTrue);

        VTImageRotationSessionCreate(kCFAllocatorDefault, 180, &_imageRotationSession180);
        VTSessionSetProperty((VTSessionRef)_imageRotationSession180,
                             kVTImageRotationPropertyKey_EnableHighSpeedTransfer,
                             kCFBooleanTrue);

        VTImageRotationSessionCreate(kCFAllocatorDefault, 270, &_imageRotationSession270);
        VTSessionSetProperty((VTSessionRef)_imageRotationSession270,
                             kVTImageRotationPropertyKey_EnableHighSpeedTransfer,
                             kCFBooleanTrue);

        _rtmpRotation = -1;
        _userIntentLive = NO;
        _mediaType = 0;
        _mediaLoop = YES;
        _mediaPaused = NO;
        _mediaRotation = -1;
        _videoDetectedRotation = -1;
        _mediaFitMode = 0;
        _performanceFPS = 30;
        _lastSourceFrameUpdate = 0;
        _lastSourceFrameReceived = 0;
        _mediaQueue = dispatch_queue_create("com.vcam.media", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - Target matching

- (BOOL)shouldInjectForCameraPosition:(int)position {
    int target = self.cameraTarget;
    return target == 0 || (position != 0 && position == target);
}

- (BOOL)blackoutImageBuffer:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = sampleBuffer
        ? CMSampleBufferGetImageBuffer(sampleBuffer) : NULL;
    return imageBuffer ? vcam_fill_black_pixel_buffer((CVPixelBufferRef)imageBuffer) : NO;
}

#pragma mark - Rotation helpers

- (int)effectiveMediaRotationForType:(int)type {
    int rot = _mediaRotation;
    if (type == 1 && rot == -1) return 0;
    if (type == 2) {
        if (rot == -1) {
            int detected = _videoDetectedRotation;
            if (detected == 90 || detected == 270) return detected;
            if (detected == 180) return 180;
            return 0;
        }
        if (rot == 90 || rot == 180 || rot == 270) return rot;
    }
    return rot;
}

- (CVPixelBufferRef)createRotImageBuffer:(CVPixelBufferRef)src
                                 session:(VTImageRotationSessionRef)session
                                swapDims:(BOOL)swapDims {
    if (!src || !session) return NULL;
    OSType fmt = CVPixelBufferGetPixelFormatType(src);
    int srcW = (int)CVPixelBufferGetWidth(src);
    int srcH = (int)CVPixelBufferGetHeight(src);
    int dstW = swapDims ? srcH : srcW;
    int dstH = swapDims ? srcW : srcH;

    NSDictionary *attrs = @{
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    CVPixelBufferRef dst = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault, (size_t)dstW, (size_t)dstH, fmt,
                            (__bridge CFDictionaryRef)attrs, &dst) != kCVReturnSuccess) {
        return NULL;
    }
    if (VTImageRotationSessionTransferImage(session, src, dst) != noErr) {
        CVPixelBufferRelease(dst);
        return NULL;
    }
    vcam_copy_color_attachments(src, dst);
    return dst;
}

- (CVPixelBufferRef)vcam_updateRotatedBuffer:(CVPixelBufferRef)buffer
                                      source:(CVPixelBufferRef)source
                                     session:(VTImageRotationSessionRef)session
                                    swapDims:(BOOL)swapDims {
    if (!source || !session) {
        if (buffer) CVPixelBufferRelease(buffer);
        return NULL;
    }
    size_t width = CVPixelBufferGetWidth(source);
    size_t height = CVPixelBufferGetHeight(source);
    if (swapDims) { size_t t = width; width = height; height = t; }
    BOOL reusable = buffer &&
        CVPixelBufferGetPixelFormatType(buffer) == CVPixelBufferGetPixelFormatType(source) &&
        CVPixelBufferGetWidth(buffer) == width &&
        CVPixelBufferGetHeight(buffer) == height;
    if (!reusable) {
        if (buffer) CVPixelBufferRelease(buffer);
        buffer = [self createRotImageBuffer:source session:session swapDims:swapDims];
        return buffer;
    }
    if (VTImageRotationSessionTransferImage(session, source, buffer) != noErr) {
        CVPixelBufferRelease(buffer);
        return NULL;
    }
    vcam_copy_color_attachments(source, buffer);
    return buffer;
}

#pragma mark - Frame input

- (void)vcam_setSourceSampleBuffer:(CMSampleBufferRef)sbuf {
    if (!sbuf) return;
    CVImageBufferRef ibuf = CMSampleBufferGetImageBuffer(sbuf);
    if (!ibuf) return;

    [_lock lock];

    CMSampleBufferRef replacement = (CMSampleBufferRef)CFRetain(sbuf);
    if (!replacement) { [_lock unlock]; return; }
    if (_liveYUVSampleBuffer) CFRelease(_liveYUVSampleBuffer);
    _liveYUVSampleBuffer = replacement;
    _sourceFrameGeneration++;

    CVPixelBufferRef src = (CVPixelBufferRef)CMSampleBufferGetImageBuffer(sbuf);
    int rot = (_mediaType == 0) ? _rtmpRotation : [self effectiveMediaRotationForType:_mediaType];
    _rotationDirty = NO;

    if (rot == 0 || rot == -1) {
        if (_pixelYUVBuffer90) {
            CVPixelBufferRelease(_pixelYUVBuffer90);
            _pixelYUVBuffer90 = NULL;
        }
    } else if (rot == 180) {
        _pixelYUVBuffer90 = [self vcam_updateRotatedBuffer:_pixelYUVBuffer90
                                                     source:src
                                                    session:_imageRotationSession180
                                                   swapDims:NO];
    } else if (rot == 270) {
        _pixelYUVBuffer90 = [self vcam_updateRotatedBuffer:_pixelYUVBuffer90
                                                     source:src
                                                    session:_imageRotationSession270
                                                   swapDims:YES];
    } else {
        _pixelYUVBuffer90 = [self vcam_updateRotatedBuffer:_pixelYUVBuffer90
                                                     source:src
                                                    session:_imageRotationSession
                                                   swapDims:YES];
    }

    [_lock unlock];

    if (_userIntentLive && !self.bLive) {
        self.bLive = YES;
    }
}

- (void)vcam_setMediaSampleBuffer:(CMSampleBufferRef)sbuf expectedType:(int)type {
    [_lock lock];
    BOOL typeSelected = (_mediaType == type);
    if (!typeSelected) { [_lock unlock]; return; }
    [self vcam_setSourceSampleBuffer:sbuf];
    [_lock unlock];
}

- (void)vcam_clearLiveFrame {
    [_lock lock];
    if (_liveYUVSampleBuffer) { CFRelease(_liveYUVSampleBuffer); _liveYUVSampleBuffer = NULL; }
    if (_pixelYUVBuffer90) { CVPixelBufferRelease(_pixelYUVBuffer90); _pixelYUVBuffer90 = NULL; }
    _lastSourceFrameReceived = 0;
    _lastSourceFrameUpdate = 0;
    [_lock unlock];
}

- (int)effectiveMediaRotationForType:(int)type {
    int rot = _mediaRotation;
    if (type == 1 && rot == -1) {
        return 0;
    }
    if (type == 2) {
        if (rot == -1) {
            int detected = _videoDetectedRotation;
            if (detected == 90 || detected == 270) return detected;
            if (detected == 180) return 180;
            return 0;
        }
        if (rot == 90 || rot == 180 || rot == 270) return rot;
        return 0;
    }
    return rot;
}

- (void)setYUVSampleBuffer:(CMSampleBufferRef)sbuf {
    if (!sbuf) return;
    [_lock lock];
    if (_mediaType != 0) { [_lock unlock]; return; }
    _lastSourceFrameReceived = CACurrentMediaTime();
    int sourceFPS = _performanceFPS;
    CFAbsoluteTime lastUpdate = _lastSourceFrameUpdate;
    CFAbsoluteTime now = CACurrentMediaTime();
    BOOL shouldDrop = sourceFPS > 0 && lastUpdate > 0 && now + 0.001 < lastUpdate;
    if (!shouldDrop && sourceFPS > 0) {
        CFTimeInterval period = 1.0 / (CFTimeInterval)sourceFPS;
        _lastSourceFrameUpdate = (lastUpdate > 0 && now - lastUpdate < period)
            ? lastUpdate + period : now + period;
    }
    if (shouldDrop) { [_lock unlock]; return; }
    if (_mediaType == 0) [self vcam_setSourceSampleBuffer:sbuf];
    [_lock unlock];
}

#pragma mark - Frame injection

- (CMSampleBufferRef)modifyImageBuffer:(CMSampleBufferRef)sampleBuffer {
  @autoreleasepool {
    if (!_bLive && !_userIntentLive) return nil;

    CVImageBufferRef destBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!destBuffer) return nil;

    [_lock lock];

    if (_userIntentLive && !_bLive) self.bLive = YES;
    if (!_bLive) {
        [_lock unlock];
        return nil;
    }
    if (!_liveYUVSampleBuffer) {
        BOOL blackedOut = vcam_fill_black_pixel_buffer((CVPixelBufferRef)destBuffer);
        [_lock unlock];
        return blackedOut ? sampleBuffer : nil;
    }

    if (_mediaType == 0 && _lastSourceFrameReceived > 0.0 &&
        CACurrentMediaTime() - _lastSourceFrameReceived > 1.0) {
        BOOL blackedOut = vcam_fill_black_pixel_buffer((CVPixelBufferRef)destBuffer);
        [_lock unlock];
        return blackedOut ? sampleBuffer : nil;
    }

    if (_rotationDirty) [self vcam_setSourceSampleBuffer:_liveYUVSampleBuffer];

    CVImageBufferRef srcBuffer = CMSampleBufferGetImageBuffer(_liveYUVSampleBuffer);
    if (!srcBuffer) {
        BOOL blackedOut = vcam_fill_black_pixel_buffer((CVPixelBufferRef)destBuffer);
        [_lock unlock];
        return blackedOut ? sampleBuffer : nil;
    }

    CVImageBufferRef transferSrc;
    int rot = (_mediaType == 0) ? _rtmpRotation : [self effectiveMediaRotationForType:_mediaType];
    if (_mediaType == 1 || _mediaType == 2) {
        transferSrc = (rot == 0) ? srcBuffer : (CVImageBufferRef)_pixelYUVBuffer90;
    } else if (rot == 0) {
        transferSrc = srcBuffer;
    } else if (rot > 0) {
        transferSrc = (CVImageBufferRef)_pixelYUVBuffer90;
    } else {
        transferSrc = srcBuffer;
    }
    if (!transferSrc) {
        BOOL blackedOut = vcam_fill_black_pixel_buffer((CVPixelBufferRef)destBuffer);
        [_lock unlock];
        return blackedOut ? sampleBuffer : nil;
    }

    BOOL success = NO;
    if (transferSrc) {
        VTPixelTransferSessionRef session = (_mediaType == 1 || _mediaType == 2)
            ? _mediaTransferSession : _pixelTransferSession;

        OSStatus status = session
            ? VTPixelTransferSessionTransferImage(session, transferSrc,
                                                   (CVPixelBufferRef)destBuffer)
            : kCVReturnError;

        if (status != noErr) {
            CFTimeInterval now = CACurrentMediaTime();
            if (now - _lastInjectionReset >= 1.0) {
                _lastInjectionReset = now;
                [self vcam_resetInjectionSession];
                session = (_mediaType == 0) ? _pixelTransferSession : _mediaTransferSession;
                if (session) status = VTPixelTransferSessionTransferImage(
                    session, transferSrc, (CVPixelBufferRef)destBuffer);
            }
        }
        if (status == noErr) success = YES;
    }

    [_lock unlock];

    if (success) {
        CVPixelBufferFillExtendedPixels((CVPixelBufferRef)destBuffer);
    }

    if (!success) {
        vcam_fill_black_pixel_buffer((CVPixelBufferRef)destBuffer);
        return nil;
    }
    return sampleBuffer;
  }
}

#pragma mark - State accessors

- (BOOL)getLive {
    [_lock lock];
    BOOL live = self.bLive || _userIntentLive;
    [_lock unlock];
    return live;
}

- (void)setLive:(BOOL)live {
    self.bLive = live;
}

- (void)setLiveUserIntent:(BOOL)intent {
    [_lock lock];
    _userIntentLive = intent;
    [_lock unlock];
    if (!intent) {
        self.bLive = NO;
        [_lock lock];
        _mediaPaused = NO;
        [_lock unlock];
        [self stopVideoReader];
        [self vcam_clearLiveFrame];
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

#pragma mark - Configuration

- (void)setMediaType:(int)type {
    if (type < 0 || type > 2) return;
    [_lock lock];
    BOOL sameType = (_mediaType == type);
    _mediaType = type;
    if (!sameType) _mediaImageGeneration++;
    _mediaPaused = NO;
    NSString *path = [_mediaPath copy];
    NSUInteger generation = _mediaImageGeneration;
    if (type != 2) _videoDetectedRotation = -1;
    if (!sameType) [self vcam_clearLiveFrame];
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
    BOOL pathChanged = ![_mediaPath isEqualToString:newPath];
    if (pathChanged) {
        _mediaPaused = NO;
        if (_normalizedImage) {
            CGImageRelease(_normalizedImage);
            _normalizedImage = NULL;
        }
        _normalizedImagePath = nil;
    }
    _mediaPath = newPath;
    if (pathChanged) _mediaImageGeneration++;
    NSString *imagePath = (_mediaType == 1) ? [_mediaPath copy] : nil;
    if (pathChanged) [self vcam_clearLiveFrame];
    [_lock unlock];

    if (imagePath) {
        [self loadImageFile:imagePath];
    } else if (_mediaType == 2) {
        [self stopVideoReader];
        NSString *videoPath = [_mediaPath copy];
        NSUInteger videoGeneration = _mediaImageGeneration;
        dispatch_async(_mediaQueue, ^{
            if (videoGeneration != self->_mediaImageGeneration || !self->_userIntentLive ||
                self->_mediaType != 2 || ![self->_mediaPath isEqualToString:videoPath]) {
                return;
            }
            self->_videoReaderRetryCount = 0;
            [self startVideoReader:videoPath];
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
                         kVTPixelTransferPropertyKey_ScalingMode,
                         scalingMode);
    [_lock unlock];
}

- (void)setPerformanceFPS:(int)fps {
    if (fps <= 0) fps = 30;
    if (fps > 60) fps = 60;
    [_lock lock];
    if (_performanceFPS == fps) { [_lock unlock]; return; }
    _performanceFPS = fps;
    _lastSourceFrameUpdate = 0;
    [_lock unlock];
}

#pragma mark - Image loading

- (void)loadImageFile:(NSString *)path {
    if (!path) return;

    [_lock lock];
    NSUInteger generation = _mediaImageGeneration;
    [_lock unlock];

    dispatch_async(_mediaQueue, ^{
      @autoreleasepool {
        [self->_lock lock];
        BOOL currentLoad = (generation == self->_mediaImageGeneration &&
                            [self->_mediaPath isEqualToString:path]);
        [self->_lock unlock];
        if (!currentLoad) return;

        NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        unsigned long long fileSize = [[fileAttrs objectForKey:NSFileSize] unsignedLongLongValue];
        if (fileSize == 0) return;

        CGImageRef cgImage = NULL;
        [self->_lock lock];
        if (self->_normalizedImage && [self->_normalizedImagePath isEqualToString:path]) {
            cgImage = CGImageRetain(self->_normalizedImage);
            [self->_lock unlock];
        } else {
            [self->_lock unlock];
            NSData *imgData = [NSData dataWithContentsOfFile:path];
            if (!imgData) return;
            CGImageSourceRef imgSource = CGImageSourceCreateWithData((CFDataRef)imgData, NULL);
            if (!imgSource) return;
            NSDictionary *thumbOpts = @{
                (NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                (NSString *)kCGImageSourceThumbnailMaxPixelSize: @1280,
            };
            cgImage = CGImageSourceCreateThumbnailAtIndex(imgSource, 0,
                                                           (__bridge CFDictionaryRef)thumbOpts);
            CFRelease(imgSource);
            if (cgImage) {
                [self->_lock lock];
                BOOL cacheCurrent = (generation == self->_mediaImageGeneration &&
                                     [self->_mediaPath isEqualToString:path]);
                if (cacheCurrent) {
                    if (self->_normalizedImage) CGImageRelease(self->_normalizedImage);
                    self->_normalizedImage = CGImageRetain(cgImage);
                    self->_normalizedImagePath = [path copy];
                }
                [self->_lock unlock];
            }
        }
        if (!cgImage) return;

        size_t w = CGImageGetWidth(cgImage);
        size_t h = CGImageGetHeight(cgImage);

        NSDictionary *attrs = @{
            (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        };
        CVPixelBufferRef pixbuf = NULL;
        CVReturn cvRet = CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                             kCVPixelFormatType_32BGRA,
                                             (__bridge CFDictionaryRef)attrs, &pixbuf);
        if (cvRet != kCVReturnSuccess || !pixbuf) {
            CGImageRelease(cgImage);
            return;
        }

        if (CVPixelBufferLockBaseAddress(pixbuf, 0) != kCVReturnSuccess) {
            CVPixelBufferRelease(pixbuf);
            CGImageRelease(cgImage);
            return;
        }
        void *baseAddr = CVPixelBufferGetBaseAddress(pixbuf);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixbuf);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (!colorSpace) {
            CVPixelBufferUnlockBaseAddress(pixbuf, 0);
            CVPixelBufferRelease(pixbuf);
            CGImageRelease(cgImage);
            return;
        }
        CGContextRef ctx = CGBitmapContextCreate(baseAddr, w, h, 8, bytesPerRow,
                                                  colorSpace,
                                                  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        if (!ctx) {
            CGColorSpaceRelease(colorSpace);
            CVPixelBufferUnlockBaseAddress(pixbuf, 0);
            CVPixelBufferRelease(pixbuf);
            CGImageRelease(cgImage);
            return;
        }
        CGContextTranslateCTM(ctx, 0, (CGFloat)h);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 1.0);
        CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
        CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cgImage);
        CGContextRelease(ctx);
        CGColorSpaceRelease(colorSpace);
        CVPixelBufferUnlockBaseAddress(pixbuf, 0);

        CMVideoFormatDescriptionRef fmt = NULL;
        CMSampleBufferRef sbuf = NULL;
        CMSampleTimingInfo timing;
        memset(&timing, 0, sizeof(timing));
        timing.duration = kCMTimeInvalid;
        timing.presentationTimeStamp = CMTimeMake(0, 600);
        timing.decodeTimeStamp = kCMTimeInvalid;
        if (CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixbuf, &fmt) == noErr && fmt) {
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixbuf, YES,
                                               NULL, NULL, fmt, &timing, &sbuf);
        }
        if (sbuf) {
            [self->_lock lock];
            BOOL stillCurrent = (generation == self->_mediaImageGeneration &&
                                 self->_mediaType == 1 &&
                                 [self->_mediaPath isEqualToString:path]);
            if (stillCurrent) [self vcam_setMediaSampleBuffer:sbuf expectedType:1];
            [self->_lock unlock];
            CFRelease(sbuf);
        }
        if (fmt) CFRelease(fmt);
        CGImageRelease(cgImage);
        CVPixelBufferRelease(pixbuf);
      }
    });
}

#pragma mark - Video file reading

- (void)startVideoReader:(NSString *)path {
  @autoreleasepool {
    if (!path) return;
    [_lock lock];
    NSUInteger sourceGeneration = _mediaImageGeneration;
    BOOL selected = (_userIntentLive && _mediaType == 2 && [_mediaPath isEqualToString:path]);
    [_lock unlock];
    if (!selected) return;

    NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    unsigned long long fileSize = [[fileAttrs objectForKey:NSFileSize] unsignedLongLongValue];
    if (fileSize == 0) return;

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL
                                            options:@{ AVURLAssetPreferPreciseDurationAndTimingKey: @YES }];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"duration"] completionHandler:^{
        dispatch_semaphore_signal(sema);
    }];
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(sema, timeout);
    if (waitResult != 0) return;

    NSError *trackError = nil;
    AVKeyValueStatus trackStatus = [asset statusOfValueForKey:@"tracks" error:&trackError];
    if (trackStatus != AVKeyValueStatusLoaded) return;

    AVAssetTrack *videoTrack = nil;
    for (AVAssetTrack *t in [asset tracksWithMediaType:AVMediaTypeVideo]) {
        videoTrack = t; break;
    }
    if (!videoTrack) return;

    CGAffineTransform transform = videoTrack.preferredTransform;
    CGFloat angle = atan2(transform.b, transform.a) * 180.0 / M_PI;
    if (angle < 0.0) angle += 360.0;
    int detectedRotation = -1;
    if (fabs(angle - 90.0) < 10.0) detectedRotation = 90;
    else if (fabs(angle - 180.0) < 10.0) detectedRotation = 180;
    else if (fabs(angle - 270.0) < 10.0) detectedRotation = 270;
    else if (fabs(angle) < 10.0 || fabs(angle - 360.0) < 10.0) detectedRotation = 0;

    NSDictionary *settings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput
        assetReaderTrackOutputWithTrack:videoTrack
                           outputSettings:settings];
    output.alwaysCopiesSampleData = NO;

    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:nil];
    if (!reader) return;
    if (![reader canAddOutput:output]) return;
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
    [_lock unlock];

    CMTime firstPTS = kCMTimeInvalid;
    CMTime lastPublishedPTS = kCMTimeInvalid;
    CFTimeInterval playbackStart = 0.0;
    while (reader.status == AVAssetReaderStatusReading) {
      @autoreleasepool {
        [_lock lock];
        BOOL stillReader = (_userIntentLive && _mediaType == 2 && [_mediaPath isEqualToString:path] &&
                            _videoReader == reader);
        BOOL paused = _mediaPaused && stillReader;
        [_lock unlock];
        if (!stillReader) break;
        if (paused) {
            firstPTS = kCMTimeInvalid;
            lastPublishedPTS = kCMTimeInvalid;
            usleep(20000);
            continue;
        }
        if (CMTIME_IS_INVALID(firstPTS)) {
            playbackStart = CACurrentMediaTime();
        }
        CMSampleBufferRef sbuf = [output copyNextSampleBuffer];
        if (!sbuf) break;

        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sbuf);
        BOOL publishFrame = YES;
        [_lock lock];
        int fps = _performanceFPS;
        [_lock unlock];
        if (fps > 0 && CMTIME_IS_VALID(pts) && CMTIME_IS_VALID(lastPublishedPTS)) {
            CMTime publishDelta = CMTimeSubtract(pts, lastPublishedPTS);
            Float64 publishSeconds = CMTimeGetSeconds(publishDelta);
            if (publishSeconds >= 0.0 && publishSeconds + 0.0005 < (1.0 / (double)fps)) {
                publishFrame = NO;
            }
        }

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
                    BOOL interrupted = _mediaPaused || _videoReader != reader || !_userIntentLive;
                    [_lock unlock];
                    if (interrupted) break;
                    usleep((useconds_t)llround(fmin(wait, 0.02) * 1000000.0));
                    wait = target - (CACurrentMediaTime() - playbackStart);
                }
                if (wait < -0.1) publishFrame = NO;
            }
        } else {
            usleep(15000);
        }

        [_lock lock];
        BOOL stillCurrent = (_userIntentLive && !_mediaPaused && _mediaType == 2 &&
                             _videoReader == reader && [_mediaPath isEqualToString:path]);
        if (stillCurrent && publishFrame) {
            [self vcam_setMediaSampleBuffer:sbuf expectedType:2];
            if (CMTIME_IS_VALID(pts)) lastPublishedPTS = pts;
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

    if (ownsReader && finalStatus == AVAssetReaderStatusCompleted) {
        NSUInteger loopGeneration = _mediaImageGeneration;
        if (_userIntentLive && !_mediaPaused && _mediaLoop && _mediaType == 2 &&
            [_mediaPath isEqualToString:path]) {
            NSString *loopPath = [path copy];
            dispatch_async(_mediaQueue, ^{
                if (loopGeneration != self->_mediaImageGeneration || !self->_userIntentLive ||
                    self->_mediaType != 2 || ![self->_mediaPath isEqualToString:loopPath]) {
                    return;
                }
                [self startVideoReader:loopPath];
            });
        }
    } else if (ownsReader) {
        [_lock lock];
        BOOL shouldRetry = (_userIntentLive && _mediaType == 2 && !_mediaPaused &&
                            _videoReaderRetryCount < 3 && [_mediaPath isEqualToString:path]);
        if (shouldRetry) _videoReaderRetryCount++;
        [_lock unlock];
        if (shouldRetry) {
            NSString *retryPath = [path copy];
            NSUInteger retryGeneration = _mediaImageGeneration;
            [self vcam_clearLiveFrame];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                           _mediaQueue, ^{
                [self->_lock lock];
                BOOL retryCurrent = (retryGeneration == self->_mediaImageGeneration && self->_userIntentLive &&
                                     self->_mediaType == 2 && !self->_mediaPaused &&
                                     (!self->_videoReader || self->_videoReader.status != AVAssetReaderStatusReading) &&
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
    if (reader) {
        if (reader.status == AVAssetReaderStatusReading) [reader cancelReading];
    }
}

- (void)dealloc {
    [self stopVideoReader];
    if (_liveYUVSampleBuffer) CFRelease(_liveYUVSampleBuffer);
    if (_pixelYUVBuffer90) CVPixelBufferRelease(_pixelYUVBuffer90);
    if (_pixelTransferSession) CFRelease(_pixelTransferSession);
    if (_mediaTransferSession) CFRelease(_mediaTransferSession);
    if (_imageRotationSession) CFRelease(_imageRotationSession);
    if (_imageRotationSession180) CFRelease(_imageRotationSession180);
    if (_imageRotationSession270) CFRelease(_imageRotationSession270);
    if (_normalizedImage) CGImageRelease(_normalizedImage);
}

@end
