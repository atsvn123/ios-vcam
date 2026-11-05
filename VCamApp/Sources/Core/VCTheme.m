#import "VCTheme.h"

static UIColor *VCHex(uint32_t rgb, CGFloat a) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:a];
}

@implementation VCTheme

+ (UIColor *)background    { return VCHex(0x0A0A0C, 1.0); }
+ (UIColor *)card          { return VCHex(0x16161A, 1.0); }
+ (UIColor *)cardBorder    { return [UIColor colorWithWhite:1.0 alpha:0.08]; }
+ (UIColor *)field         { return VCHex(0x222228, 1.0); }
+ (UIColor *)textPrimary   { return [UIColor colorWithWhite:0.96 alpha:1.0]; }
+ (UIColor *)textSecondary { return [UIColor colorWithWhite:0.60 alpha:1.0]; }
+ (UIColor *)accentPink    { return VCHex(0x8B5CF6, 1.0); }  // tím chủ đạo
+ (UIColor *)accentRed     { return VCHex(0xA855F7, 1.0); }  // tím sáng
+ (UIColor *)accentOrange  { return VCHex(0x6D28D9, 1.0); }  // tím đậm
+ (UIColor *)liveGreen     { return VCHex(0x34D399, 1.0); }

+ (NSArray *)brandGradientColors {
    // Không dùng gradient nữa — trả về 1 màu solid tím
    return @[ (id)[self accentPink].CGColor,
              (id)[self accentPink].CGColor ];
}

+ (CGFloat)cornerRadius { return 16.0; }
+ (CGFloat)gutter       { return 16.0; }

+ (UIFont *)sectionTitleFont { return [UIFont systemFontOfSize:12.0 weight:UIFontWeightBold]; }
+ (UIFont *)bodyFont         { return [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular]; }
+ (UIFont *)captionFont      { return [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular]; }

+ (void)applyGlobalAppearance {
    UITabBarAppearance *tab = [[UITabBarAppearance alloc] init];
    [tab configureWithOpaqueBackground];
    tab.backgroundColor = [self card];
    tab.shadowColor = [self cardBorder];
    UITabBarItemAppearance *item = tab.stackedLayoutAppearance;
    item.normal.iconColor = [self textSecondary];
    item.normal.titleTextAttributes = @{ NSForegroundColorAttributeName: [self textSecondary] };
    item.selected.iconColor = [self accentPink];
    item.selected.titleTextAttributes = @{ NSForegroundColorAttributeName: [self accentPink] };
    [UITabBar appearance].standardAppearance = tab;
    if (@available(iOS 15.0, *)) {
        [UITabBar appearance].scrollEdgeAppearance = tab;
    }

    UINavigationBarAppearance *nav = [[UINavigationBarAppearance alloc] init];
    [nav configureWithOpaqueBackground];
    nav.backgroundColor = [self background];
    nav.shadowColor = [UIColor clearColor];
    nav.titleTextAttributes = @{ NSForegroundColorAttributeName: [self textPrimary] };
    nav.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: [self textPrimary] };
    [UINavigationBar appearance].standardAppearance = nav;
    [UINavigationBar appearance].scrollEdgeAppearance = nav;
    [UINavigationBar appearance].compactAppearance = nav;
    [UINavigationBar appearance].tintColor = [self accentPink];
}

+ (void)styleSegmentedControl:(UISegmentedControl *)seg {
    seg.backgroundColor = [self field];
    seg.selectedSegmentTintColor = [self accentPink];
    [seg setTitleTextAttributes:@{ NSForegroundColorAttributeName: [self textSecondary],
                                   NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium] }
                       forState:UIControlStateNormal];
    [seg setTitleTextAttributes:@{ NSForegroundColorAttributeName: [UIColor whiteColor],
                                   NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold] }
                       forState:UIControlStateSelected];
}

@end
