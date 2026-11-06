#import "VCSourceViewController.h"
#import "VCSettingsStore.h"
#import "VCTheme.h"
#import "VCCardView.h"
#import "VCLiveButton.h"
#import <PhotosUI/PhotosUI.h>

@interface VCSourceViewController () <UITextFieldDelegate, PHPickerViewControllerDelegate>
@end

@implementation VCSourceViewController {
    UIScrollView *_scroll;
    UIStackView *_stack;

    VCCardView *_sourceCard;
    UISegmentedControl *_sourceSeg;

    UIStackView *_rtmpPanel;
    UITextField *_rtmpField;

    UIStackView *_mediaPanel;
    UIButton *_pickMediaButton;
    UILabel *_mediaNameLabel;

    VCCardView *_fpsCard;
    UISegmentedControl *_fpsSeg;
    UILabel *_fpsHint;

    VCCardView *_frameCard;
    UISegmentedControl *_frameSeg;
    UILabel *_frameHint;

    VCLiveButton *_liveButton;

    VCSourceType _lastSourceType;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [VCTheme background];
    _lastSourceType = (VCSourceType)-1;
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

    [self buildSourceCard];
    [self buildRTMPPanel];
    [self buildMediaPanel];
    [self buildFPSCard];
    [self buildFrameCard];

    [_stack addArrangedSubview:_sourceCard];
    [_stack addArrangedSubview:_fpsCard];
    [_stack addArrangedSubview:_frameCard];

    _liveButton = [[VCLiveButton alloc] init];
    [_liveButton addTarget:self action:@selector(liveTapped) forControlEvents:UIControlEventTouchUpInside];
    [_stack addArrangedSubview:_liveButton];
    [_stack setCustomSpacing:20 afterView:_frameCard];
}

- (void)buildSourceCard {
    _sourceCard = [[VCCardView alloc] initWithTitle:@"Nguồn" dotColor:[VCTheme accentPink]];

    _sourceSeg = [[UISegmentedControl alloc] initWithItems:@[ @"RTMP", @"Ảnh", @"Video" ]];
    [VCTheme styleSegmentedControl:_sourceSeg];
    [_sourceSeg.heightAnchor constraintEqualToConstant:36].active = YES;
    [_sourceSeg addTarget:self action:@selector(sourceChanged:) forControlEvents:UIControlEventValueChanged];
    [_sourceCard addArrangedSubview:_sourceSeg];
}

- (void)buildRTMPPanel {
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

    _rtmpPanel = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self caption:@"RTMP URL"], _rtmpField, rtmpActions ]];
    _rtmpPanel.axis = UILayoutConstraintAxisVertical;
    _rtmpPanel.spacing = 8;
}

- (void)buildMediaPanel {
    _pickMediaButton = [self smallButton:@"Chọn ảnh..." icon:@"photo.on.rectangle" action:@selector(pickMedia)];
    [_pickMediaButton.heightAnchor constraintEqualToConstant:44].active = YES;
    _mediaNameLabel = [self caption:@""];
    _mediaNameLabel.numberOfLines = 2;
    _mediaPanel = [[UIStackView alloc] initWithArrangedSubviews:@[ _pickMediaButton, _mediaNameLabel ]];
    _mediaPanel.axis = UILayoutConstraintAxisVertical;
    _mediaPanel.spacing = 8;
}

- (void)buildFPSCard {
    _fpsCard = [[VCCardView alloc] initWithTitle:@"Hiệu năng / FPS" dotColor:[VCTheme accentRed]];
    _fpsSeg = [[UISegmentedControl alloc] initWithItems:@[ @"Tự động", @"10", @"15", @"30", @"60" ]];
    [VCTheme styleSegmentedControl:_fpsSeg];
    [_fpsSeg.heightAnchor constraintEqualToConstant:36].active = YES;
    [_fpsSeg addTarget:self action:@selector(fpsChanged:) forControlEvents:UIControlEventValueChanged];
    [_fpsCard addArrangedSubview:_fpsSeg];
    _fpsHint = [self caption:@""];
    [_fpsCard addArrangedSubview:_fpsHint];
}

- (void)buildFrameCard {
    _frameCard = [[VCCardView alloc] initWithTitle:@"Khung hình" dotColor:[VCTheme accentOrange]];
    _frameSeg = [[UISegmentedControl alloc] initWithItems:@[ @"Fit", @"Trim" ]];
    [VCTheme styleSegmentedControl:_frameSeg];
    [_frameSeg.heightAnchor constraintEqualToConstant:36].active = YES;
    [_frameSeg addTarget:self action:@selector(frameChanged:) forControlEvents:UIControlEventValueChanged];
    [_frameCard addArrangedSubview:_frameSeg];
    _frameHint = [self caption:@""];
    [_frameCard addArrangedSubview:_frameHint];
}

#pragma mark - Panel switching

- (void)showPanelForSource:(VCSourceType)type animated:(BOOL)animated {
    if (_lastSourceType == type) return;

    if (_lastSourceType == VCSourceTypeRTMP) {
        [_rtmpPanel removeFromSuperview];
    } else if (_lastSourceType != (VCSourceType)-1) {
        [_mediaPanel removeFromSuperview];
    }

    UIView *panel = (type == VCSourceTypeRTMP) ? _rtmpPanel : _mediaPanel;

    if (animated) {
        panel.alpha = 0;
        [_sourceCard addArrangedSubview:panel];
        [UIView animateWithDuration:0.25 animations:^{
            panel.alpha = 1;
            [self.view layoutIfNeeded];
        }];
    } else {
        [_sourceCard addArrangedSubview:panel];
    }

    _lastSourceType = type;
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
    [self showPanelForSource:type animated:YES];

    if (!_rtmpField.isFirstResponder) _rtmpField.text = s.rtmpURL;

    BOOL isVideo = (type == VCSourceTypeVideo);
    [_pickMediaButton setTitle:(isVideo ? @" Chọn video..." : @" Chọn ảnh...") forState:UIControlStateNormal];
    [_pickMediaButton setImage:[UIImage systemImageNamed:(isVideo ? @"film" : @"photo.on.rectangle")]
                      forState:UIControlStateNormal];
    _mediaNameLabel.text = s.mediaName.length ? s.mediaName
                                              : (isVideo ? @"Chưa chọn video" : @"Chưa chọn ảnh");

    BOOL showFPS = (type != VCSourceTypePhoto);
    _fpsSeg.selectedSegmentIndex = showFPS ? VCIndexForFPS(s.fps) : 0;
    _fpsSeg.enabled = showFPS;
    _fpsSeg.alpha = showFPS ? 1.0 : 0.45;

    if (type == VCSourceTypePhoto) {
        _fpsHint.text = @"Nguồn Ảnh: chỉ inject 1 frame tĩnh, không tốn CPU.";
    } else if (isVideo) {
        _fpsHint.text = (s.fps == 0)
            ? @"Nguồn Video: phát theo FPS gốc của file video."
            : [NSString stringWithFormat:@"Nguồn Video: giới hạn %ld FPS, bỏ qua frame thừa.", (long)s.fps];
    } else {
        _fpsHint.text = @"FPS thấp giảm tải CPU và nhiệt.";
    }

    _frameSeg.selectedSegmentIndex = s.frameMode;
    _frameHint.text = (s.frameMode == VCFrameModeFit)
        ? @"Fit: giữ trọn khung hình, có thể có viền đen."
        : @"Trim: cắt cho đầy khung camera, không có viền.";

    [_liveButton setLive:s.isLive animated:NO];
    _sourceSeg.enabled = !s.isLive;
    _sourceSeg.alpha = s.isLive ? 0.45 : 1.0;
}

#pragma mark - Actions

- (void)sourceChanged:(UISegmentedControl *)seg {
    [self.view endEditing:YES];
    VCSourceType newType = (VCSourceType)seg.selectedSegmentIndex;
    [VCSettingsStore shared].sourceType = newType;
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
    VCSourceType type = [VCSettingsStore shared].sourceType;
    PHPickerFilter *filter = (type == VCSourceTypeVideo) ? [PHPickerFilter videosFilter]
                                                         : [PHPickerFilter imagesFilter];
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = filter;
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)liveTapped {
    [self.view endEditing:YES];
    VCSettingsStore *s = [VCSettingsStore shared];
    if (!s.isLive && s.sourceType != VCSourceTypeRTMP && !s.mediaName.length) {
        [self toast:(s.sourceType == VCSourceTypeVideo ? @"Hãy chọn video trước" : @"Hãy chọn ảnh trước")];
        return;
    }
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

#pragma mark - PHPickerViewControllerDelegate

- (void)promptVideoFPS:(NSString *)filename path:(NSString *)path store:(VCSettingsStore *)s {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Cài đặt Video"
                         message:[NSString stringWithFormat:@"File: %@\nChọn độ phân giải và FPS", filename]
                  preferredStyle:UIAlertControllerStyleActionSheet];

    void (^apply)(NSInteger, NSInteger) = ^(NSInteger res, NSInteger fps) {
        s.videoResolution = res;
        s.fps = fps;
        s.mediaName = filename;
        s.mediaPath = path;
    };

    [alert addAction:[UIAlertAction actionWithTitle:@"Tự động (gốc, FPS gốc)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { apply(0, 0); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"720p — 15 FPS"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { apply(720, 15); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"720p — 30 FPS"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { apply(720, 30); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"720p — 60 FPS"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { apply(720, 60); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"1080p — 15 FPS"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { apply(1080, 15); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"1080p — 30 FPS"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { apply(1080, 30); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"1080p — 60 FPS"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { apply(1080, 60); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect =
        CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 0, 0);
    alert.popoverPresentationController.permittedArrowDirections = 0;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;

    VCSourceType type = [VCSettingsStore shared].sourceType;
    BOOL isVideo = (type == VCSourceTypeVideo);
    NSString *typeId = isVideo ? @"public.movie" : @"public.image";

    if (![result.itemProvider hasItemConformingToTypeIdentifier:typeId]) {
        [self toast:@"Định dạng không hỗ trợ"];
        return;
    }

    NSString *tmpDir = @"/tmp/vcam";
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *dirAttrs = @{
        NSFileProtectionKey: NSFileProtectionNone,
        NSFilePosixPermissions: @0755,
    };
    [fm createDirectoryAtPath:tmpDir withIntermediateDirectories:YES attributes:dirAttrs error:nil];
    [fm setAttributes:dirAttrs ofItemAtPath:tmpDir error:nil];

    [result.itemProvider loadFileRepresentationForTypeIdentifier:typeId
        completionHandler:^(NSURL *url, NSError *error) {
        if (!url) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self toast:@"Không thể tải file"]; });
            return;
        }
        NSString *filename = url.lastPathComponent;
        NSString *extension = filename.pathExtension.length ? filename.pathExtension : (isVideo ? @"mov" : @"jpg");
        NSString *storedName = [NSString stringWithFormat:@"vcam_%@.%@", NSUUID.UUID.UUIDString, extension];
        NSString *destPath = [tmpDir stringByAppendingPathComponent:storedName];
        NSError *copyErr = nil;
        BOOL ok = [fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:destPath] error:&copyErr];
        if (ok) {
            NSDictionary *fileAttrs = @{
                NSFileProtectionKey: NSFileProtectionNone,
                NSFilePosixPermissions: @0644,
            };
            [fm setAttributes:fileAttrs ofItemAtPath:destPath error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) { [self toast:@"Không thể sao chép file"]; return; }
            VCSettingsStore *s = [VCSettingsStore shared];
            if (isVideo) {
                [self promptVideoFPS:filename path:destPath store:s];
            } else {
                s.mediaName = filename;
                s.mediaPath = destPath;
            }
        });
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
