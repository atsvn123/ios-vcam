#import "VCSourceViewController.h"
#import "VCSettingsStore.h"
#import "VCTheme.h"
#import "VCCardView.h"
#import "VCLiveButton.h"

@interface VCSourceViewController () <UITextFieldDelegate>
@end

@implementation VCSourceViewController {
    UIScrollView *_scroll;
    UIStackView *_stack;

    // Preview
    UILabel *_previewTitle;
    UILabel *_previewInfo;
    UIImageView *_previewIcon;

    // Nguồn
    UISegmentedControl *_sourceSeg;
    UIView *_rtmpPanel;
    UITextField *_rtmpField;
    UIView *_mediaPanel;
    UIButton *_pickMediaButton;
    UILabel *_mediaNameLabel;

    // FPS / khung hình
    UISegmentedControl *_fpsSeg;
    UISegmentedControl *_frameSeg;
    UILabel *_frameHint;

    VCLiveButton *_liveButton;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [VCTheme background];
    [self buildLayout];
    [self reloadFromStore];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storeChanged:)
                                                 name:VCSettingsDidChangeNotification
                                               object:nil];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self.view
                                                                         action:@selector(endEditing:)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Layout

- (void)buildLayout {
    _scroll = [[UIScrollView alloc] init];
    _scroll.alwaysBounceVertical = YES;
    _scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scroll];

    _stack = [[UIStackView alloc] init];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 14;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];

    CGFloat g = [VCTheme gutter];
    UILayoutGuide *content = _scroll.contentLayoutGuide;
    UILayoutGuide *frame = _scroll.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [_stack.topAnchor constraintEqualToAnchor:content.topAnchor constant:8],
        [_stack.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [_stack.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor constant:g],
        [_stack.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-g],
    ]];

    [_stack addArrangedSubview:[self buildPreviewCard]];
    [_stack addArrangedSubview:[self buildSourceCard]];
    [_stack addArrangedSubview:[self buildFPSCard]];
    [_stack addArrangedSubview:[self buildFrameCard]];

    _liveButton = [[VCLiveButton alloc] init];
    [_liveButton addTarget:self action:@selector(liveTapped) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:_liveButton];
    [_stack setCustomSpacing:20 afterView:_stack.arrangedSubviews[_stack.arrangedSubviews.count - 2]];
}

- (UIView *)buildPreviewCard {
    UIView *box = [[UIView alloc] init];
    box.backgroundColor = [UIColor blackColor];
    box.layer.cornerRadius = [VCTheme cornerRadius];
    box.layer.borderWidth = 1;
    box.layer.borderColor = [VCTheme cardBorder].CGColor;
    box.clipsToBounds = YES;

    _previewIcon = [[UIImageView alloc] init];
    _previewIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.25];
    _previewIcon.contentMode = UIViewContentModeScaleAspectFit;
    _previewIcon.translatesAutoresizingMaskIntoConstraints = NO;

    _previewTitle = [[UILabel alloc] init];
    _previewTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _previewTitle.textColor = [VCTheme textPrimary];
    _previewTitle.translatesAutoresizingMaskIntoConstraints = NO;

    _previewInfo = [[UILabel alloc] init];
    _previewInfo.font = [VCTheme captionFont];
    _previewInfo.textColor = [VCTheme textSecondary];
    _previewInfo.numberOfLines = 2;
    _previewInfo.translatesAutoresizingMaskIntoConstraints = NO;

    [box addSubview:_previewIcon];
    [box addSubview:_previewTitle];
    [box addSubview:_previewInfo];
    [NSLayoutConstraint activateConstraints:@[
        [box.heightAnchor constraintEqualToAnchor:box.widthAnchor multiplier:9.0 / 16.0],
        [_previewIcon.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],
        [_previewIcon.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],
        [_previewIcon.widthAnchor constraintEqualToConstant:44],
        [_previewIcon.heightAnchor constraintEqualToConstant:44],
        [_previewTitle.topAnchor constraintEqualToAnchor:box.topAnchor constant:12],
        [_previewTitle.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:14],
        [_previewTitle.trailingAnchor constraintLessThanOrEqualToAnchor:box.trailingAnchor constant:-14],
        [_previewInfo.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:14],
        [_previewInfo.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-14],
        [_previewInfo.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-12],
    ]];
    return box;
}

- (UIView *)buildSourceCard {
    VCCardView *card = [[VCCardView alloc] initWithTitle:@"Nguồn" dotColor:[VCTheme accentPink]];

    _sourceSeg = [[UISegmentedControl alloc] initWithItems:@[ @"RTMP", @"Ảnh", @"Video" ]];
    [VCTheme styleSegmentedControl:_sourceSeg];
    [_sourceSeg.heightAnchor constraintEqualToConstant:36].active = YES;
    [_sourceSeg addTarget:self action:@selector(sourceChanged:) forControlEvents:UIControlEventValueChanged];
    [card addArrangedSubview:_sourceSeg];

    // RTMP panel
    _rtmpField = [[UITextField alloc] init];
    _rtmpField.backgroundColor = [VCTheme field];
    _rtmpField.layer.cornerRadius = 10;
    _rtmpField.textColor = [VCTheme textPrimary];
    _rtmpField.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _rtmpField.attributedPlaceholder = [[NSAttributedString alloc]
        initWithString:[VCSettingsStore defaultRTMPURL]
            attributes:@{ NSForegroundColorAttributeName: [VCTheme textSecondary] }];
    _rtmpField.keyboardType = UIKeyboardTypeURL;
    _rtmpField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _rtmpField.autocorrectionType = UITextAutocorrectionTypeNo;
    _rtmpField.returnKeyType = UIReturnKeyDone;
    _rtmpField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _rtmpField.delegate = self;
    _rtmpField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    _rtmpField.leftViewMode = UITextFieldViewModeAlways;
    [_rtmpField.heightAnchor constraintEqualToConstant:44].active = YES;

    UIButton *copyBtn = [self smallButton:@"Sao chép" icon:@"doc.on.doc" action:@selector(copyRTMP)];
    UIButton *resetBtn = [self smallButton:@"Mặc định" icon:@"arrow.counterclockwise" action:@selector(resetRTMP)];
    UIStackView *rtmpActions = [[UIStackView alloc] initWithArrangedSubviews:@[ copyBtn, resetBtn ]];
    rtmpActions.spacing = 10;
    rtmpActions.distribution = UIStackViewDistributionFillEqually;

    UIStackView *rtmp = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self caption:@"RTMP URL"], _rtmpField, rtmpActions ]];
    rtmp.axis = UILayoutConstraintAxisVertical;
    rtmp.spacing = 8;
    _rtmpPanel = rtmp;
    [card addArrangedSubview:_rtmpPanel];

    // Media panel (Ảnh / Video)
    _pickMediaButton = [self smallButton:@"Chọn ảnh..." icon:@"photo.on.rectangle" action:@selector(pickMedia)];
    [_pickMediaButton.heightAnchor constraintEqualToConstant:44].active = YES;
    _mediaNameLabel = [self caption:@""];
    _mediaNameLabel.numberOfLines = 2;
    UIStackView *media = [[UIStackView alloc] initWithArrangedSubviews:@[ _pickMediaButton, _mediaNameLabel ]];
    media.axis = UILayoutConstraintAxisVertical;
    media.spacing = 8;
    _mediaPanel = media;
    [card addArrangedSubview:_mediaPanel];

    return card;
}

- (UIView *)buildFPSCard {
    VCCardView *card = [[VCCardView alloc] initWithTitle:@"Hiệu năng / FPS" dotColor:[VCTheme accentRed]];
    _fpsSeg = [[UISegmentedControl alloc] initWithItems:@[ @"Tĩnh 1", @"10", @"15", @"30" ]];
    [VCTheme styleSegmentedControl:_fpsSeg];
    [_fpsSeg.heightAnchor constraintEqualToConstant:36].active = YES;
    [_fpsSeg addTarget:self action:@selector(fpsChanged:) forControlEvents:UIControlEventValueChanged];
    [card addArrangedSubview:_fpsSeg];
    [card addArrangedSubview:[self caption:@"FPS thấp giảm tải CPU và nhiệt. Nguồn Ảnh luôn chạy 1 FPS."]];
    return card;
}

- (UIView *)buildFrameCard {
    VCCardView *card = [[VCCardView alloc] initWithTitle:@"Khung hình" dotColor:[VCTheme accentOrange]];
    _frameSeg = [[UISegmentedControl alloc] initWithItems:@[ @"Fit", @"Trim" ]];
    [VCTheme styleSegmentedControl:_frameSeg];
    [_frameSeg.heightAnchor constraintEqualToConstant:36].active = YES;
    [_frameSeg addTarget:self action:@selector(frameChanged:) forControlEvents:UIControlEventValueChanged];
    [card addArrangedSubview:_frameSeg];
    _frameHint = [self caption:@""];
    [card addArrangedSubview:_frameHint];
    return card;
}

#pragma mark - Helpers

- (UILabel *)caption:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [VCTheme captionFont];
    l.textColor = [VCTheme textSecondary];
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)smallButton:(NSString *)title icon:(NSString *)icon action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:[@" " stringByAppendingString:title] forState:UIControlStateNormal];
    [b setImage:[UIImage systemImageNamed:icon] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    b.tintColor = [VCTheme textPrimary];
    b.backgroundColor = [VCTheme field];
    b.layer.cornerRadius = 10;
    [b.heightAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

static NSInteger VCIndexForFPS(NSInteger fps) {
    NSUInteger i = [[VCSettingsStore supportedFPS] indexOfObject:@(fps)];
    return i == NSNotFound ? 3 : (NSInteger)i;
}

#pragma mark - State

- (void)storeChanged:(NSNotification *)note {
    [self reloadFromStore];
}

- (void)reloadFromStore {
    VCSettingsStore *s = [VCSettingsStore shared];
    VCSourceType type = s.sourceType;

    _sourceSeg.selectedSegmentIndex = type;
    _rtmpPanel.hidden = (type != VCSourceTypeRTMP);
    _mediaPanel.hidden = (type == VCSourceTypeRTMP);
    if (!_rtmpField.isFirstResponder) _rtmpField.text = s.rtmpURL;

    BOOL isVideo = (type == VCSourceTypeVideo);
    [_pickMediaButton setTitle:(isVideo ? @" Chọn video..." : @" Chọn ảnh...") forState:UIControlStateNormal];
    [_pickMediaButton setImage:[UIImage systemImageNamed:(isVideo ? @"film" : @"photo.on.rectangle")]
                      forState:UIControlStateNormal];
    _mediaNameLabel.text = s.mediaName.length ? s.mediaName
                                              : (isVideo ? @"Chưa chọn video" : @"Chưa chọn ảnh");

    // Ảnh tĩnh luôn 1 FPS: khoá segment FPS.
    BOOL photo = (type == VCSourceTypePhoto);
    _fpsSeg.selectedSegmentIndex = photo ? 0 : VCIndexForFPS(s.fps);
    _fpsSeg.enabled = !photo;
    _fpsSeg.alpha = photo ? 0.45 : 1.0;

    _frameSeg.selectedSegmentIndex = s.frameMode;
    _frameHint.text = (s.frameMode == VCFrameModeFit)
        ? @"Fit: giữ trọn khung hình, có thể có viền đen."
        : @"Trim: cắt cho đầy khung camera, không có viền.";

    [_liveButton setLive:s.isLive animated:NO];
    // Đang live thì khoá đổi nguồn để tránh đổi giữa chừng.
    _sourceSeg.enabled = !s.isLive;
    _sourceSeg.alpha = s.isLive ? 0.45 : 1.0;

    [self updatePreview];
}

- (void)updatePreview {
    VCSettingsStore *s = [VCSettingsStore shared];
    NSArray *names = @[ @"RTMP", @"Ảnh", @"Video" ];
    NSArray *icons = @[ @"dot.radiowaves.left.and.right", @"photo", @"film" ];
    _previewTitle.text = [NSString stringWithFormat:@"Preview %@", names[s.sourceType]];
    _previewIcon.image = [UIImage systemImageNamed:icons[s.sourceType]];
    NSString *fps = (s.sourceType == VCSourceTypePhoto) ? @"1" : [@(s.fps) stringValue];
    _previewInfo.text = [NSString stringWithFormat:@"%@ · %@ FPS · %@\nChưa có tín hiệu",
                         s.isLive ? @"● LIVE" : @"○ Tắt", fps,
                         s.frameMode == VCFrameModeFit ? @"Fit" : @"Trim"];
}

#pragma mark - Actions

- (void)sourceChanged:(UISegmentedControl *)seg {
    [self.view endEditing:YES];
    [UIView animateWithDuration:0.25 animations:^{
        [VCSettingsStore shared].sourceType = (VCSourceType)seg.selectedSegmentIndex;
        [self.view layoutIfNeeded];
    }];
}

- (void)fpsChanged:(UISegmentedControl *)seg {
    [VCSettingsStore shared].fps = [[VCSettingsStore supportedFPS][seg.selectedSegmentIndex] integerValue];
}

- (void)frameChanged:(UISegmentedControl *)seg {
    [VCSettingsStore shared].frameMode = (VCFrameMode)seg.selectedSegmentIndex;
}

- (void)copyRTMP {
    [UIPasteboard generalPasteboard].string = [VCSettingsStore shared].rtmpURL;
    [self toast:@"Đã sao chép RTMP URL"];
}

- (void)resetRTMP {
    [VCSettingsStore shared].rtmpURL = [VCSettingsStore defaultRTMPURL];
    _rtmpField.text = [VCSettingsStore defaultRTMPURL];
}

- (void)pickMedia {
    // TODO(port): PHPickerViewController / UIDocumentPicker + copy file sang thư mục tweak đọc được.
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Chưa khả dụng"
                                                               message:@"Chọn media sẽ được port từ bản cũ ở bước sau."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)liveTapped {
    [self.view endEditing:YES];
    VCSettingsStore *s = [VCSettingsStore shared];
    if (!s.isLive && s.sourceType != VCSourceTypeRTMP && !s.mediaName.length) {
        [self toast:(s.sourceType == VCSourceTypeVideo ? @"Hãy chọn video trước" : @"Hãy chọn ảnh trước")];
        return;
    }
    // TODO(port): gửi lệnh start/stop sang tweak qua bridge. Hiện chỉ đổi state UI.
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];
    s.live = !s.isLive;
    [_liveButton setLive:s.isLive animated:YES];
}

- (void)toast:(NSString *)text {
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    l.textColor = [UIColor whiteColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    l.layer.cornerRadius = 12;
    l.clipsToBounds = YES;
    l.alpha = 0;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:l];
    [NSLayoutConstraint activateConstraints:@[
        [l.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [l.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [l.heightAnchor constraintEqualToConstant:40],
        [l.widthAnchor constraintEqualToConstant:MAX(200, l.intrinsicContentSize.width + 32)],
    ]];
    [UIView animateWithDuration:0.2 animations:^{ l.alpha = 1; } completion:^(BOOL f) {
        [UIView animateWithDuration:0.3 delay:1.4 options:0 animations:^{ l.alpha = 0; }
                         completion:^(BOOL f2) { [l removeFromSuperview]; }];
    }];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NSString *v = [textField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![v.lowercaseString hasPrefix:@"rtmp://"]) {
        [self toast:@"URL phải bắt đầu bằng rtmp://"];
        textField.text = [VCSettingsStore shared].rtmpURL;
        return;
    }
    [VCSettingsStore shared].rtmpURL = v;
}

@end
