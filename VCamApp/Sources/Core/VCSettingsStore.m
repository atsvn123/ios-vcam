#import "VCSettingsStore.h"
#import "VCClientSocket.h"

NSNotificationName const VCSettingsDidChangeNotification = @"VCSettingsDidChangeNotification";

static NSString *const kSourceType = @"vc.sourceType";
static NSString *const kFPS        = @"vc.fps";
static NSString *const kFrameMode  = @"vc.frameMode";
static NSString *const kRTMPURL    = @"vc.rtmpURL";
static NSString *const kMediaName  = @"vc.mediaName";
static NSString *const kMediaPath  = @"vc.mediaPath";
static NSString *const kLive       = @"vc.live";
static NSString *const kCameraTarget = @"vc.cameraTarget";
static NSString *const kVideoResolution = @"vc.videoResolution";
static NSString *const kMediaRotation = @"vc.mediaRotation";
static NSString *const kMediaMirror = @"vc.mediaMirror";
static NSString *const kRearRotationOffset = @"vc.rearRotationOffset";
static NSString *const kFrontRotationOffset = @"vc.frontRotationOffset";
static NSString *const kRearMirror = @"vc.rearMirror";
static NSString *const kFrontMirror = @"vc.frontMirror";

@implementation VCSettingsStore {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared {
    static VCSettingsStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

+ (NSArray<NSNumber *> *)supportedFPS { return @[ @0, @10, @15, @30, @60 ]; }
+ (NSString *)defaultRTMPURL { return @"rtmp://127.0.0.1:1935/live"; }

- (instancetype)init {
    if ((self = [super init])) {
        _defaults = [NSUserDefaults standardUserDefaults];
        [_defaults registerDefaults:@{
            kSourceType: @(VCSourceTypeRTMP),
            kFPS:        @0,
            kFrameMode:  @(VCFrameModeFit),
            kRTMPURL:    [VCSettingsStore defaultRTMPURL],
            kLive:       @NO,
            kCameraTarget: @0,
            kMediaRotation: @(-1),
            kMediaMirror: @NO,
            kRearRotationOffset: @0,
            kFrontRotationOffset: @0,
            kRearMirror: @(-1),
            kFrontMirror: @(-1),
        }];
        _socket = [[VCClientSocket alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_socketDidConnect:)
                                                     name:VCClientSocketDidConnectNotification
                                                   object:_socket];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_cameraResolutionUpdated:)
                                                     name:VCClientSocketCameraResolutionNotification
                                                   object:_socket];
        [_socket connectToHost:@"127.0.0.1" port:22222];
    }
    return self;
}

- (void)_socketDidConnect:(NSNotification *)note {
    VCSourceType src = self.sourceType;
    [_socket sendInt32:1020 value:(int32_t)src];
    [_socket sendInt32:1027 value:(int32_t)self.fps];
    [_socket sendInt32:1025 value:(int32_t)self.frameMode];
    [_socket sendInt32:1029 value:(int32_t)self.cameraTarget];
    [_socket sendInt32:1035 value:(int32_t)self.mediaRotation];
    [_socket sendInt32:1036 value:(int32_t)(self.mediaMirror ? 1 : 0)];
    [_socket sendCameraRotationOffset:(int32_t)self.rearRotationOffset position:1];
    [_socket sendCameraRotationOffset:(int32_t)self.frontRotationOffset position:2];
    [_socket sendCameraMirror:(self.rearMirror == 1)
                    hasOverride:(self.rearMirror >= 0) position:1];
    [_socket sendCameraMirror:(self.frontMirror == 1)
                    hasOverride:(self.frontMirror >= 0) position:2];
    NSString *path = self.mediaPath;
    if (path.length) {
        [_socket sendFileAtPath:path type:(int32_t)src];
    }
    if (self.isLive) {
        if (src == VCSourceTypeRTMP) {
            [_socket sendInt32:1000];
        } else {
            [_socket sendInt32:1023 value:1];
        }
    }
}

- (void)_cameraResolutionUpdated:(NSNotification *)note {
    [self notify:@"cameraResolution"];
}

- (void)notify:(NSString *)key {
    [[NSNotificationCenter defaultCenter] postNotificationName:VCSettingsDidChangeNotification
                                                        object:self
                                                      userInfo:@{ @"key": key }];
}

#pragma mark - Properties

- (VCSourceType)sourceType {
    NSInteger v = [_defaults integerForKey:kSourceType];
    return (v < VCSourceTypeRTMP || v > VCSourceTypeVideo) ? VCSourceTypeRTMP : (VCSourceType)v;
}
- (void)setSourceType:(VCSourceType)sourceType {
    if (sourceType == self.sourceType) return;
    [_defaults setInteger:sourceType forKey:kSourceType];
    [_defaults removeObjectForKey:kMediaName];
    [_defaults removeObjectForKey:kMediaPath];
    [_socket sendInt32:1020 value:(int32_t)sourceType];
    [self notify:@"sourceType"];
}

- (NSInteger)fps {
    NSInteger v = [_defaults integerForKey:kFPS];
    return [[VCSettingsStore supportedFPS] containsObject:@(v)] ? v : 0;
}
- (void)setFps:(NSInteger)fps {
    if (![[VCSettingsStore supportedFPS] containsObject:@(fps)] || fps == self.fps) return;
    [_defaults setInteger:fps forKey:kFPS];
    [_socket sendInt32:1027 value:(int32_t)fps];
    [self notify:@"fps"];
}

- (VCFrameMode)frameMode {
    return [_defaults integerForKey:kFrameMode] == VCFrameModeTrim ? VCFrameModeTrim : VCFrameModeFit;
}
- (void)setFrameMode:(VCFrameMode)frameMode {
    if (frameMode == self.frameMode) return;
    [_defaults setInteger:frameMode forKey:kFrameMode];
    [_socket sendInt32:1025 value:(int32_t)frameMode];
    [self notify:@"frameMode"];
}

- (NSString *)rtmpURL {
    NSString *v = [_defaults stringForKey:kRTMPURL];
    return v.length ? v : [VCSettingsStore defaultRTMPURL];
}
- (void)setRtmpURL:(NSString *)rtmpURL {
    NSString *v = [rtmpURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([v isEqualToString:self.rtmpURL]) return;
    [_defaults setObject:v forKey:kRTMPURL];
    [self notify:@"rtmpURL"];
}

- (NSString *)mediaName { return [_defaults stringForKey:kMediaName]; }
- (void)setMediaName:(NSString *)mediaName {
    if (mediaName) [_defaults setObject:mediaName forKey:kMediaName];
    else [_defaults removeObjectForKey:kMediaName];
    [self notify:@"mediaName"];
}

- (NSString *)mediaPath { return [_defaults stringForKey:kMediaPath]; }
- (void)setMediaPath:(NSString *)mediaPath {
    if (mediaPath) {
        [_defaults setObject:mediaPath forKey:kMediaPath];
        // The tweak runs in mediaserverd and cannot read this app's sandbox,
        // so the file contents are streamed over the socket.
        [_socket sendFileAtPath:mediaPath type:(int32_t)self.sourceType];
    } else {
        [_defaults removeObjectForKey:kMediaPath];
    }
    [self notify:@"mediaPath"];
}

- (NSInteger)cameraTarget { return [_defaults integerForKey:kCameraTarget]; }
- (void)setCameraTarget:(NSInteger)cameraTarget {
    if (cameraTarget == self.cameraTarget) return;
    [_defaults setInteger:cameraTarget forKey:kCameraTarget];
    [_socket sendInt32:1029 value:(int32_t)cameraTarget];
    [self notify:@"cameraTarget"];
}

- (NSInteger)videoResolution { return [_defaults integerForKey:kVideoResolution]; }
- (void)setVideoResolution:(NSInteger)videoResolution {
    [_defaults setInteger:videoResolution forKey:kVideoResolution];
    [self notify:@"videoResolution"];
}

- (NSInteger)mediaRotation { return [_defaults integerForKey:kMediaRotation]; }
- (void)setMediaRotation:(NSInteger)mediaRotation {
    if (mediaRotation == self.mediaRotation) return;
    [_defaults setInteger:mediaRotation forKey:kMediaRotation];
    [_socket sendInt32:1035 value:(int32_t)mediaRotation];
    [self notify:@"mediaRotation"];
}

- (BOOL)mediaMirror { return [_defaults boolForKey:kMediaMirror]; }
- (void)setMediaMirror:(BOOL)mediaMirror {
    if (mediaMirror == self.mediaMirror) return;
    [_defaults setBool:mediaMirror forKey:kMediaMirror];
    [_socket sendInt32:1036 value:(int32_t)(mediaMirror ? 1 : 0)];
    [self notify:@"mediaMirror"];
}

- (NSInteger)rearRotationOffset { return [_defaults integerForKey:kRearRotationOffset]; }
- (void)setRearRotationOffset:(NSInteger)offset {
    [_defaults setInteger:offset forKey:kRearRotationOffset];
    [_socket sendCameraRotationOffset:offset position:1];
    [self notify:@"rearRotationOffset"];
}

- (NSInteger)frontRotationOffset { return [_defaults integerForKey:kFrontRotationOffset]; }
- (void)setFrontRotationOffset:(NSInteger)offset {
    [_defaults setInteger:offset forKey:kFrontRotationOffset];
    [_socket sendCameraRotationOffset:offset position:2];
    [self notify:@"frontRotationOffset"];
}

- (NSInteger)rearMirror { return [_defaults integerForKey:kRearMirror]; }
- (void)setRearMirror:(NSInteger)mirror {
    [_defaults setInteger:mirror forKey:kRearMirror];
    [_socket sendCameraMirror:(mirror == 1) hasOverride:(mirror >= 0) position:1];
    [self notify:@"rearMirror"];
}

- (NSInteger)frontMirror { return [_defaults integerForKey:kFrontMirror]; }
- (void)setFrontMirror:(NSInteger)mirror {
    [_defaults setInteger:mirror forKey:kFrontMirror];
    [_socket sendCameraMirror:(mirror == 1) hasOverride:(mirror >= 0) position:2];
    [self notify:@"frontMirror"];
}

- (BOOL)isLive { return [_defaults boolForKey:kLive]; }
- (void)setLive:(BOOL)live {
    if (live == self.isLive) return;
    [_defaults setBool:live forKey:kLive];
    VCSourceType src = self.sourceType;
    if (src == VCSourceTypeRTMP) {
        [_socket sendInt32:live ? 1000 : 1001];
    } else {
        [_socket sendInt32:1023 value:(int32_t)(live ? 1 : 0)];
    }
    [self notify:@"live"];
}

- (void)resetToDefaults {
    for (NSString *k in @[ kSourceType, kFPS, kFrameMode, kRTMPURL, kMediaName, kMediaPath,
                           kLive, kCameraTarget, kMediaRotation, kMediaMirror,
                           kRearRotationOffset, kFrontRotationOffset,
                           kRearMirror, kFrontMirror ]) {
        [_defaults removeObjectForKey:k];
    }
    [_socket sendInt32:1001];
    [self notify:@"*"];
}

@end
