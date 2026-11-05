#import "VCSettingsStore.h"

NSNotificationName const VCSettingsDidChangeNotification = @"VCSettingsDidChangeNotification";

static NSString *const kSourceType = @"vc.sourceType";
static NSString *const kFPS        = @"vc.fps";
static NSString *const kFrameMode  = @"vc.frameMode";
static NSString *const kRTMPURL    = @"vc.rtmpURL";
static NSString *const kMediaName  = @"vc.mediaName";
static NSString *const kLive       = @"vc.live";

@implementation VCSettingsStore {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared {
    static VCSettingsStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[self alloc] init]; });
    return s;
}

+ (NSArray<NSNumber *> *)supportedFPS { return @[ @1, @10, @15, @30 ]; }
+ (NSString *)defaultRTMPURL { return @"rtmp://127.0.0.1:1935/live"; }

- (instancetype)init {
    if ((self = [super init])) {
        _defaults = [NSUserDefaults standardUserDefaults];
        [_defaults registerDefaults:@{
            kSourceType: @(VCSourceTypeRTMP),
            kFPS:        @30,
            kFrameMode:  @(VCFrameModeFit),
            kRTMPURL:    [VCSettingsStore defaultRTMPURL],
            kLive:       @NO,
        }];
    }
    return self;
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
    // Nguồn đổi thì media đã chọn cho nguồn cũ không còn hợp lệ.
    [_defaults removeObjectForKey:kMediaName];
    [self notify:@"sourceType"];
}

- (NSInteger)fps {
    NSInteger v = [_defaults integerForKey:kFPS];
    return [[VCSettingsStore supportedFPS] containsObject:@(v)] ? v : 30;
}
- (void)setFps:(NSInteger)fps {
    if (![[VCSettingsStore supportedFPS] containsObject:@(fps)] || fps == self.fps) return;
    [_defaults setInteger:fps forKey:kFPS];
    [self notify:@"fps"];
}

- (VCFrameMode)frameMode {
    return [_defaults integerForKey:kFrameMode] == VCFrameModeTrim ? VCFrameModeTrim : VCFrameModeFit;
}
- (void)setFrameMode:(VCFrameMode)frameMode {
    if (frameMode == self.frameMode) return;
    [_defaults setInteger:frameMode forKey:kFrameMode];
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

- (BOOL)isLive { return [_defaults boolForKey:kLive]; }
- (void)setLive:(BOOL)live {
    if (live == self.isLive) return;
    [_defaults setBool:live forKey:kLive];
    [self notify:@"live"];
}

- (void)resetToDefaults {
    for (NSString *k in @[ kSourceType, kFPS, kFrameMode, kRTMPURL, kMediaName, kLive ]) {
        [_defaults removeObjectForKey:k];
    }
    [self notify:@"*"];
}

@end
