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

/// Trạng thái UI của app, lưu trong NSUserDefaults.
/// Hiện chỉ là state cục bộ; khi port chức năng sẽ nối sang bridge
/// gửi tới tweak (mediaserverd) tại một chỗ duy nhất là class này.
@interface VCSettingsStore : NSObject

+ (instancetype)shared;

@property (nonatomic) VCSourceType sourceType;
@property (nonatomic) NSInteger fps;              // 1, 10, 15, 30
@property (nonatomic) VCFrameMode frameMode;
@property (nonatomic, copy) NSString *rtmpURL;
@property (nonatomic, copy, nullable) NSString *mediaName; // tên file ảnh/video đã chọn (placeholder)
@property (nonatomic, getter=isLive) BOOL live;

+ (NSArray<NSNumber *> *)supportedFPS;
+ (NSString *)defaultRTMPURL;

- (void)resetToDefaults;

@end

NS_ASSUME_NONNULL_END
