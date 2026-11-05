#import "VCLivenessViewController.h"
#import "VCTheme.h"
#import "VCCardView.h"

// Khoá NSUserDefaults tạm cho khung UI. Khi port BINFlash sẽ chuyển sang prefs của tweak.
static NSString *const kFlashOn     = @"vc.liveness.flash";
static NSString *const kSpeed       = @"vc.liveness.speed";
static NSString *const kBrightness  = @"vc.liveness.brightness";
static NSString *const kRegion      = @"vc.liveness.region";
static NSString *const kAutoColor   = @"vc.liveness.autoColor";

@implementation VCLivenessViewController {
    UIStackView *_stack;
    UISwitch *_flashSwitch;
    UISwitch *_autoColorSwitch;
    NSMutableArray<UIView *> *_dependentRows;  // mờ đi khi flash tắt
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [VCTheme background];
    _dependentRows = [NSMutableArray array];

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kFlashOn: @NO, kSpeed: @50, kBrightness: @50, kRegion: @50, kAutoColor: @NO,
    }];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.alwaysBounceVertical = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scroll];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 14;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:_stack];

    CGFloat g = [VCTheme gutter];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:8],
        [_stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [_stack.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:g],
        [_stack.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-g],
    ]];

    [_stack addArrangedSubview:[self buildFlashCard]];
    [_stack addArrangedSubview:[self buildColorCard]];
    [_stack addArrangedSubview:[self buildRegionCard]];
    [_stack addArrangedSubview:[self noteLabel]];

    [self updateEnabled];
}

#pragma mark - Cards

- (UIView *)buildFlashCard {
    VCCardView *card = [[VCCardView alloc] initWithTitle:@"Flash" dotColor:[VCTheme accentPink]];
    _flashSwitch = [[UISwitch alloc] init];
    _flashSwitch.onTintColor = [VCTheme accentPink];
    _flashSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:kFlashOn];
    [_flashSwitch addTarget:self action:@selector(flashToggled:) forControlEvents:UIControlEventValueChanged];
    [card addArrangedSubview:[self row:@"Bật hiệu ứng flash" control:_flashSwitch]];

    UIView *speed = [self sliderRow:@"Tốc độ" key:kSpeed];
    UIView *bright = [self sliderRow:@"Độ sáng" key:kBrightness];
    [_dependentRows addObjectsFromArray:@[ speed, bright ]];
    [card addArrangedSubview:speed];
    [card addArrangedSubview:bright];
    return card;
}

- (UIView *)buildColorCard {
    VCCardView *card = [[VCCardView alloc] initWithTitle:@"Màu" dotColor:[VCTheme accentRed]];
    _autoColorSwitch = [[UISwitch alloc] init];
    _autoColorSwitch.onTintColor = [VCTheme accentPink];
    _autoColorSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:kAutoColor];
    [_autoColorSwitch addTarget:self action:@selector(autoColorToggled:) forControlEvents:UIControlEventValueChanged];
    UIView *autoRow = [self row:@"Tự nhận màu từ app" control:_autoColorSwitch];

    UIButton *pick = [UIButton buttonWithType:UIButtonTypeSystem];
    [pick setTitle:@" Chọn màu thủ công" forState:UIControlStateNormal];
    [pick setImage:[UIImage systemImageNamed:@"eyedropper"] forState:UIControlStateNormal];
    pick.tintColor = [VCTheme textPrimary];
    pick.backgroundColor = [VCTheme field];
    pick.layer.cornerRadius = 10;
    [pick.heightAnchor constraintEqualToConstant:42].active = YES;
    [pick addTarget:self action:@selector(notPorted) forControlEvents:UIControlEventTouchUpInside];

    [_dependentRows addObjectsFromArray:@[ autoRow, pick ]];
    [card addArrangedSubview:autoRow];
    [card addArrangedSubview:pick];
    return card;
}

- (UIView *)buildRegionCard {
    VCCardView *card = [[VCCardView alloc] initWithTitle:@"Vùng khuôn mặt" dotColor:[VCTheme accentOrange]];
    UIView *region = [self sliderRow:@"Kích thước vùng" key:kRegion];

    UIButton *manual = [UIButton buttonWithType:UIButtonTypeSystem];
    [manual setTitle:@" Đặt vị trí thủ công" forState:UIControlStateNormal];
    [manual setImage:[UIImage systemImageNamed:@"viewfinder"] forState:UIControlStateNormal];
    manual.tintColor = [VCTheme textPrimary];
    manual.backgroundColor = [VCTheme field];
    manual.layer.cornerRadius = 10;
    [manual.heightAnchor constraintEqualToConstant:42].active = YES;
    [manual addTarget:self action:@selector(notPorted) forControlEvents:UIControlEventTouchUpInside];

    [_dependentRows addObjectsFromArray:@[ region, manual ]];
    [card addArrangedSubview:region];
    [card addArrangedSubview:manual];
    return card;
}

- (UILabel *)noteLabel {
    UILabel *l = [[UILabel alloc] init];
    l.text = @"Khung UI. Hiệu ứng liveness sẽ được port từ bản cũ ở bước sau.";
    l.font = [VCTheme captionFont];
    l.textColor = [VCTheme textSecondary];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 0;
    return l;
}

#pragma mark - Row helpers

- (UIView *)row:(NSString *)title control:(UIView *)control {
    UILabel *l = [[UILabel alloc] init];
    l.text = title;
    l.font = [VCTheme bodyFont];
    l.textColor = [VCTheme textPrimary];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ l, control ]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    return row;
}

- (UIView *)sliderRow:(NSString *)title key:(NSString *)key {
    UILabel *l = [[UILabel alloc] init];
    l.text = title;
    l.font = [VCTheme bodyFont];
    l.textColor = [VCTheme textPrimary];

    UILabel *value = [[UILabel alloc] init];
    value.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    value.textColor = [VCTheme textSecondary];
    value.textAlignment = NSTextAlignmentRight;
    value.tag = 100;

    UIStackView *head = [[UIStackView alloc] initWithArrangedSubviews:@[ l, value ]];

    UISlider *slider = [[UISlider alloc] init];
    slider.minimumValue = 0;
    slider.maximumValue = 100;
    slider.minimumTrackTintColor = [VCTheme accentPink];
    slider.value = [[NSUserDefaults standardUserDefaults] floatForKey:key];
    slider.accessibilityIdentifier = key;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    value.text = [NSString stringWithFormat:@"%.0f", slider.value];

    UIStackView *col = [[UIStackView alloc] initWithArrangedSubviews:@[ head, slider ]];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 6;
    return col;
}

#pragma mark - Actions

- (void)flashToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kFlashOn];
    [UIView animateWithDuration:0.2 animations:^{ [self updateEnabled]; }];
}

- (void)autoColorToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kAutoColor];
}

- (void)sliderChanged:(UISlider *)slider {
    float v = roundf(slider.value);
    [[NSUserDefaults standardUserDefaults] setFloat:v forKey:slider.accessibilityIdentifier];
    UIStackView *col = (UIStackView *)slider.superview;
    UILabel *value = [col.arrangedSubviews.firstObject viewWithTag:100];
    value.text = [NSString stringWithFormat:@"%.0f", v];
}

- (void)updateEnabled {
    BOOL on = _flashSwitch.on;
    for (UIView *v in _dependentRows) {
        v.userInteractionEnabled = on;
        v.alpha = on ? 1.0 : 0.4;
    }
}

- (void)notPorted {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Chưa khả dụng"
                                                               message:@"Chức năng này sẽ được port ở bước sau."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
