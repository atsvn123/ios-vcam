#import "VCMediaServerHooks.h"
#import <substrate.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <IOSurface/IOSurfaceRef.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <string.h>
#import "VCBridge.h"
#import "VCLiveEngine.h"

static IMP orig_emitSampleBuffer = NULL;
static IMP orig_sourceNodeEmitVideoSampleBuffer = NULL;
static BOOL g_emitHookInstalled = NO;
static BOOL g_sourceHookInstalled = NO;
static CFStringRef const kVCamCameraPositionAttachment = CFSTR("VCamCameraPosition");
static char kVCamPositionCacheKey;

static int vcam_cached_position(id object) {
    if (!object) return 0;
    NSNumber *value = objc_getAssociatedObject(object, &kVCamPositionCacheKey);
    int position = [value intValue];
    return (position == 1 || position == 2) ? position : 0;
}

static void vcam_cache_position(id object, int position) {
    if (!object || position == 0) return;
    objc_setAssociatedObject(object, &kVCamPositionCacheKey,
                             @(position), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static int vcam_position_from_sample_buffer(CMSampleBufferRef sbuf) {
    if (!sbuf) return 0;
    CFTypeRef value = CMGetAttachment(sbuf, kVCamCameraPositionAttachment, NULL);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) return 0;
    int position = 0;
    if (CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &position) &&
        (position == 1 || position == 2)) {
        return position;
    }
    return 0;
}

static void vcam_set_position_attachment(CMSampleBufferRef sbuf, int position) {
    if (!sbuf || (position != 1 && position != 2)) return;
    if (vcam_position_from_sample_buffer(sbuf) == position) return;
    int value = position;
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &value);
    if (!number) return;
    CMSetAttachment((CMAttachmentBearerRef)sbuf, kVCamCameraPositionAttachment,
                    number, kCMAttachmentMode_ShouldPropagate);
    CFRelease(number);
}

static int vcam_position_from_object(id object) {
    if (!object) return 0;
    int cached = vcam_cached_position(object);
    if (cached) return cached;
    if ([object respondsToSelector:@selector(position)]) {
        int value = ((int (*)(id, SEL))objc_msgSend)(object, @selector(position));
        if (value == 1 || value == 2) {
            vcam_cache_position(object, value);
            return value;
        }
    }
    for (Class cls = [object class]; cls; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            const char *encoding = ivar_getTypeEncoding(ivars[i]);
            if (!encoding || encoding[0] != '@') continue;
            id candidate = object_getIvar(object, ivars[i]);
            if (!candidate || ![candidate respondsToSelector:@selector(position)]) continue;
            int value = ((int (*)(id, SEL))objc_msgSend)(candidate, @selector(position));
            if (value == 1 || value == 2) {
                free(ivars);
                vcam_cache_position(object, value);
                return value;
            }
        }
        free(ivars);
    }
    return 0;
}

static int vcam_camera_position_for_node(id node, __unsafe_unretained id *seen, int seenCount, int depth) {
    if (!node || depth > 16) return 0;
    for (int i = 0; i < seenCount; i++) {
        if (seen[i] == node) return 0;
    }
    if (seenCount < 32) seen[seenCount++] = node;

    Class sourceClass = objc_getClass("BWMultiStreamCameraSourceNode");
    if (sourceClass && [node isKindOfClass:sourceClass]) {
        Ivar deviceIvar = class_getInstanceVariable([node class], "_captureDevice");
        if (deviceIvar && strcmp(ivar_getTypeEncoding(deviceIvar), "@") == 0) {
            id device = object_getIvar(node, deviceIvar);
            if (device && [device respondsToSelector:@selector(position)]) {
                int value = (int)((int (*)(id, SEL))objc_msgSend)(device, @selector(position));
                if (value == 1 || value == 2) return value;
            }
        }
        Ivar posIvar = class_getInstanceVariable([node class], "_position");
        if (posIvar && strcmp(ivar_getTypeEncoding(posIvar), "i") == 0) {
            ptrdiff_t offset = ivar_getOffset(posIvar);
            int value = 0;
            memcpy(&value, ((const uint8_t *)(__bridge void *)node) + offset, sizeof(value));
            if (value == 1 || value == 2) return value;
        }
        @try {
            NSNumber *position = [node valueForKey:@"position"];
            int value = [position intValue];
            if (value == 1 || value == 2) return value;
        } @catch (__unused NSException *e) {}
    }

    if (![node respondsToSelector:@selector(inputs)]) return 0;
    NSArray *inputs = [node inputs];
    if (![inputs isKindOfClass:[NSArray class]]) return 0;
    for (id input in inputs) {
        if (![input respondsToSelector:@selector(connection)]) continue;
        id connection = [input connection];
        if (!connection || ![connection respondsToSelector:@selector(output)]) continue;
        id upstreamOutput = [connection output];
        if (!upstreamOutput || ![upstreamOutput respondsToSelector:@selector(node)]) continue;
        int position = vcam_camera_position_for_node([upstreamOutput node], seen, seenCount, depth + 1);
        if (position == 1 || position == 2) return position;
    }
    return 0;
}

static int vcam_camera_position_for_output(id output) {
    if (!output || ![output respondsToSelector:@selector(node)]) return 0;
    int cached = vcam_cached_position(output);
    if (cached) return cached;
    __unsafe_unretained id seen[32] = {0};
    int position = vcam_camera_position_for_node([output node], seen, 0, 0);
    if (position) vcam_cache_position(output, position);
    return position;
}

static int hook_sourceNodeWillEmitVideoSampleBuffer(id self, SEL _cmd,
                                                     CMSampleBufferRef sbuf,
                                                     BOOL drivesCameraControls,
                                                     BOOL deliversStills) {
    if (!VCamIsEnabled()) {
        return ((int (*)(id, SEL, CMSampleBufferRef, BOOL, BOOL))orig_sourceNodeEmitVideoSampleBuffer)(
            self, _cmd, sbuf, drivesCameraControls, deliversStills);
    }
    @autoreleasepool {
        VCLiveEngine *manager = [VCLiveEngine existingInstance];
        BOOL live = manager && [manager getLive];
        int position = live ? vcam_position_from_object(self) : 0;
        if (live && (position == 1 || position == 2)) {
            vcam_set_position_attachment(sbuf, position);
        }
        return ((int (*)(id, SEL, CMSampleBufferRef, BOOL, BOOL))orig_sourceNodeEmitVideoSampleBuffer)(
            self, _cmd, sbuf, drivesCameraControls, deliversStills);
    }
}

static void hook_emitSampleBuffer(id self, SEL _cmd, CMSampleBufferRef sbuf) {
    if (!VCamIsEnabled()) {
        ((void (*)(id, SEL, CMSampleBufferRef))orig_emitSampleBuffer)(self, _cmd, sbuf);
        return;
    }
    @autoreleasepool {
        id node = [self respondsToSelector:@selector(node)] ? [self node] : nil;
        Class sourceClass = objc_getClass("BWMultiStreamCameraSourceNode");
        Class legacySourceClass = objc_getClass("BWCameraSourceNode");
        BOOL sourceOutput = (sourceClass && [node isKindOfClass:sourceClass]) ||
                            (legacySourceClass && [node isKindOfClass:legacySourceClass]);

        if (!sbuf || !sourceOutput) {
            ((void (*)(id, SEL, CMSampleBufferRef))orig_emitSampleBuffer)(self, _cmd, sbuf);
            return;
        }

        BOOL suppressOriginal = NO;
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sbuf);
        if (imageBuffer) {
            size_t width  = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            VCLiveEngine *state = [VCLiveEngine existingInstance];
            BOOL isLive = state && [state getLive];
            if (isLive) {
                int cameraPosition = vcam_position_from_sample_buffer(sbuf);
                if (cameraPosition == 0) cameraPosition = vcam_camera_position_for_output(self);
                if (cameraPosition == 1 || cameraPosition == 2) {
                    vcam_set_position_attachment(sbuf, cameraPosition);
                }

                BOOL targetMatches = [state shouldInjectForCameraPosition:cameraPosition];
                if (state.cameraTarget != 0 && cameraPosition == 0) {
                    // suppress orig only if blackout itself fails (buffer unwritable)
                    suppressOriginal = ![state blackoutImageBuffer:sbuf];
                    targetMatches = NO;
                }
                if (targetMatches) {
                    CFAbsoluteTime nowTS = CFAbsoluteTimeGetCurrent();
                    double elapsed = nowTS - g_lastResolutionUpdate;
                    if (g_lastResolutionUpdate <= 0.1 || elapsed > 3.0) {
                        g_lastResolutionUpdate = CFAbsoluteTimeGetCurrent();
                        VCBridge *bridge = [VCBridge sharedInstance];
                        [bridge setResolution:(unsigned int)width height:(unsigned int)height];
                    }
                    // modifyImageBuffer: writes pixels in-place into sbuf's CVPixelBuffer.
                    // On success (non-nil): suppressOriginal stays NO — orig IS called with
                    // the modified pixels so the downstream graph receives our content.
                    // On failure (nil): try blackout; suppress orig only if blackout also fails.
                    if (![state modifyImageBuffer:sbuf]) {
                        suppressOriginal = ![state blackoutImageBuffer:sbuf];
                    }
                }
            }
        }
        if (!suppressOriginal) {
            ((void (*)(id, SEL, CMSampleBufferRef))orig_emitSampleBuffer)(self, _cmd, sbuf);
        }
    }
}

void installMediaServerHooks(void) {
    Class cls;

    cls = objc_getClass("BWNodeOutput");
    if (!g_emitHookInstalled && cls && class_getInstanceMethod(cls, @selector(emitSampleBuffer:))) {
        MSHookMessageEx(cls, @selector(emitSampleBuffer:),
                        (IMP)hook_emitSampleBuffer, (IMP *)&orig_emitSampleBuffer);
        g_emitHookInstalled = (orig_emitSampleBuffer != NULL);
    }

    cls = objc_getClass("BWFigVideoCaptureStream");
    if (!g_sourceHookInstalled && cls && class_getInstanceMethod(
            cls, @selector(sourceNodeWillEmitVideoSampleBuffer:drivesCameraControls:deliversStills:))) {
        MSHookMessageEx(cls,
                        @selector(sourceNodeWillEmitVideoSampleBuffer:drivesCameraControls:deliversStills:),
                        (IMP)hook_sourceNodeWillEmitVideoSampleBuffer,
                        (IMP *)&orig_sourceNodeEmitVideoSampleBuffer);
        g_sourceHookInstalled = (orig_sourceNodeEmitVideoSampleBuffer != NULL);
    }
}
