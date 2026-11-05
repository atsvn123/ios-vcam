#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Màu, font, kích thước dùng chung. Bảng màu tím (purple).
@interface VCTheme : NSObject

+ (UIColor *)background;      // nền app (gần đen)
+ (UIColor *)card;            // nền card
+ (UIColor *)cardBorder;      // viền card
+ (UIColor *)field;           // nền ô nhập / segment
+ (UIColor *)textPrimary;
+ (UIColor *)textSecondary;
+ (UIColor *)accentPink;      // #8B5CF6 — tím chủ đạo
+ (UIColor *)accentRed;       // #A855F7 — tím sáng (phụ)
+ (UIColor *)accentOrange;    // #6D28D9 — tím đậm (phụ)
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
