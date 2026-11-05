#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VCSourceType) {
    VCSourceTypeRTMP  = 0,
    VCSourceTypePhoto = 1,
    VCSourceTypeVideo = 2,
};

typedef NS_ENUM(NSInteger, VCFrameMode) {
    VCFrameModeFit  = 0,
    VCFrameModeTrim = 1,
};

/// Post khi bất kỳ giá trị nào thay đổi. userInfo[@"key"] = tên property.
extern NSNotificationName const VCSettingsDidChangeNotification;

@class VCClientSocket;

@interface VCSettingsStore : NSObject

@property (nonatomic, readonly) VCClientSocket *socket;

+ (instancetype)shared;

@property (nonatomic) VCSourceType sourceType;
@property (nonatomic) NSInteger fps;              // 0=auto, 10, 15, 30
@property (nonatomic) VCFrameMode frameMode;
@property (nonatomic, copy) NSString *rtmpURL;
@property (nonatomic, copy, nullable) NSString *mediaName;
@property (nonatomic, copy, nullable) NSString *mediaPath;
@property (nonatomic, getter=isLive) BOOL live;
@property (nonatomic) NSInteger cameraTarget;    // 0=both, 1=rear, 2=front
@property (nonatomic) NSInteger videoResolution; // 0=auto, 720, 1080

+ (NSArray<NSNumber *> *)supportedFPS;
+ (NSString *)defaultRTMPURL;

- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
