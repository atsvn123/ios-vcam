#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Màu, font, kích thước dùng chung. Bảng màu lấy từ logo (gradient hồng -> cam).
@interface VCTheme : NSObject

+ (UIColor *)background;      // nền app (gần đen)
+ (UIColor *)card;            // nền card
+ (UIColor *)cardBorder;      // viền card
+ (UIColor *)field;           // nền ô nhập / segment
+ (UIColor *)textPrimary;
+ (UIColor *)textSecondary;
+ (UIColor *)accentPink;      // #F850B3
+ (UIColor *)accentRed;       // #FF4059
+ (UIColor *)accentOrange;    // #FFA924
+ (UIColor *)liveGreen;

/// Các stop của gradient thương hiệu (CGColor).
+ (NSArray *)brandGradientColors;

+ (CGFloat)cornerRadius;      // 16
+ (CGFloat)gutter;            // 16

+ (UIFont *)sectionTitleFont;
+ (UIFont *)bodyFont;
+ (UIFont *)captionFont;

+ (void)applyGlobalAppearance;
+ (void)styleSegmentedControl:(UISegmentedControl *)seg;

@end

NS_ASSUME_NONNULL_END
