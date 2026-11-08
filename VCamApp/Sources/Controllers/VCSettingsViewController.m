#import "VCSettingsViewController.h"
#import "VCSettingsStore.h"
#import "VCTheme.h"

static NSString *const kControlMenu  = @"vc.controlMenu";    // nút nổi trong app khác

typedef NS_ENUM(NSInteger, VCSection) {
    VCSectionCamera = 0,
    VCSectionOrientation,
    VCSectionGeneral,
    VCSectionReset,
    VCSectionAbout,
    VCSectionCount,
};

@implementation VCSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [VCTheme background];
    self.tableView.separatorColor = [VCTheme cardBorder];
    self.tableView.tableHeaderView = [self buildHeader];
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ kControlMenu: @NO }];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadTableView)
                                                 name:VCSettingsDidChangeNotification
                                               object:nil];
}

- (UIView *)buildHeader {
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 170)];

    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Logo"]];
    logo.contentMode = UIViewContentModeScaleAspectFill;
    logo.layer.cornerRadius = 22;
    logo.layer.cornerCurve = kCACornerCurveContinuous;
    logo.clipsToBounds = YES;
    logo.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *name = [[UILabel alloc] init];
    name.text = @"VCam";
    name.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    name.textColor = [VCTheme textPrimary];
    name.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *ver = [[UILabel alloc] init];
    ver.text = [NSString stringWithFormat:@"Phiên bản %@", [self versionString]];
    ver.font = [VCTheme captionFont];
    ver.textColor = [VCTheme textSecondary];
    ver.translatesAutoresizingMaskIntoConstraints = NO;

    [h addSubview:logo];
    [h addSubview:name];
    [h addSubview:ver];
    [NSLayoutConstraint activateConstraints:@[
        [logo.topAnchor constraintEqualToAnchor:h.topAnchor constant:12],
        [logo.centerXAnchor constraintEqualToAnchor:h.centerXAnchor],
        [logo.widthAnchor constraintEqualToConstant:88],
        [logo.heightAnchor constraintEqualToConstant:88],
        [name.topAnchor constraintEqualToAnchor:logo.bottomAnchor constant:10],
        [name.centerXAnchor constraintEqualToAnchor:h.centerXAnchor],
        [ver.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:2],
        [ver.centerXAnchor constraintEqualToAnchor:h.centerXAnchor],
    ]];
    return h;
}

- (NSString *)versionString {
    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    return [NSString stringWithFormat:@"%@ (%@)", info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return VCSectionCount; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case VCSectionCamera:  return 1;
        case VCSectionOrientation: return 6;
        case VCSectionGeneral: return 1;
        case VCSectionReset:   return 1;
        case VCSectionAbout:   return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case VCSectionCamera:  return @"Camera bị fake";
        case VCSectionOrientation: return @"Xoay & đảo hình";
        case VCSectionGeneral: return @"Chung";
        case VCSectionAbout:   return @"Thông tin";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case VCSectionCamera:  return @"Chọn camera sẽ bị thay bằng nguồn VCam.";
        case VCSectionOrientation:
            return @"Mặc định VCam tự bù theo hướng của máy. Nếu hình bị lệch, dùng phần bù để chỉnh thủ công cho từng camera.";
        case VCSectionGeneral: return @"Hiện nút điều khiển nổi trong các app dùng camera.";
        case VCSectionReset:   return @"Đưa nguồn, FPS, khung hình, RTMP URL về mặc định và tắt LIVE.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.backgroundColor = [VCTheme card];
    c.textLabel.textColor = [VCTheme textPrimary];
    c.detailTextLabel.textColor = [VCTheme textSecondary];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];

    switch (ip.section) {
        case VCSectionCamera: {
            UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[ @"Cả hai", @"Cam sau", @"Cam trước" ]];
            [VCTheme styleSegmentedControl:seg];
            NSInteger v = [VCSettingsStore shared].cameraTarget;
            seg.selectedSegmentIndex = (v < 0 || v > 2) ? 0 : v;
            [seg addTarget:self action:@selector(cameraTargetChanged:) forControlEvents:UIControlEventValueChanged];
            seg.translatesAutoresizingMaskIntoConstraints = NO;
            [c.contentView addSubview:seg];
            [NSLayoutConstraint activateConstraints:@[
                [seg.leadingAnchor constraintEqualToAnchor:c.contentView.layoutMarginsGuide.leadingAnchor],
                [seg.trailingAnchor constraintEqualToAnchor:c.contentView.layoutMarginsGuide.trailingAnchor],
                [seg.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:10],
                [seg.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-10],
                [seg.heightAnchor constraintEqualToConstant:34],
            ]];
            break;
        }
        case VCSectionOrientation: {
            VCSettingsStore *s = [VCSettingsStore shared];
            if (ip.row == 1) {
                c.textLabel.text = @"Đảo hình nguồn";
                UISwitch *sw = [[UISwitch alloc] init];
                sw.onTintColor = [VCTheme accentPink];
                sw.on = s.mediaMirror;
                [sw addTarget:self action:@selector(mediaMirrorToggled:)
              forControlEvents:UIControlEventValueChanged];
                c.accessoryView = sw;
                break;
            }

            NSString *title;
            UISegmentedControl *seg;
            if (ip.row == 0) {
                title = @"Xoay nguồn";
                seg = [[UISegmentedControl alloc]
                    initWithItems:@[ @"Tự động", @"0°", @"90°", @"180°", @"270°" ]];
                NSInteger v = s.mediaRotation;
                NSInteger idx = 0;
                if (v == 0) idx = 1; else if (v == 90) idx = 2;
                else if (v == 180) idx = 3; else if (v == 270) idx = 4;
                seg.selectedSegmentIndex = idx;
                [seg addTarget:self action:@selector(mediaRotationChanged:)
              forControlEvents:UIControlEventValueChanged];
            } else if (ip.row == 2 || ip.row == 3) {
                BOOL rear = (ip.row == 2);
                title = rear ? @"Bù xoay cam sau" : @"Bù xoay cam trước";
                seg = [[UISegmentedControl alloc]
                    initWithItems:@[ @"0°", @"90°", @"180°", @"270°" ]];
                NSInteger off = rear ? s.rearRotationOffset : s.frontRotationOffset;
                NSInteger idx = 0;
                if (off == 90) idx = 1; else if (off == 180) idx = 2; else if (off == 270) idx = 3;
                seg.selectedSegmentIndex = idx;
                seg.tag = rear ? 0 : 1;
                [seg addTarget:self action:@selector(rotationOffsetChanged:)
              forControlEvents:UIControlEventValueChanged];
            } else {
                BOOL rear = (ip.row == 4);
                title = rear ? @"Đảo hình cam sau" : @"Đảo hình cam trước";
                seg = [[UISegmentedControl alloc]
                    initWithItems:@[ @"Tự động", @"Tắt", @"Bật" ]];
                NSInteger v = rear ? s.rearMirror : s.frontMirror;
                seg.selectedSegmentIndex = (v < 0) ? 0 : (v == 0 ? 1 : 2);
                seg.tag = rear ? 0 : 1;
                [seg addTarget:self action:@selector(cameraMirrorChanged:)
              forControlEvents:UIControlEventValueChanged];
            }
            [VCTheme styleSegmentedControl:seg];

            UILabel *caption = [[UILabel alloc] init];
            caption.text = title;
            caption.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            caption.textColor = [VCTheme textSecondary];
            caption.translatesAutoresizingMaskIntoConstraints = NO;

            seg.translatesAutoresizingMaskIntoConstraints = NO;
            [c.contentView addSubview:caption];
            [c.contentView addSubview:seg];
            [NSLayoutConstraint activateConstraints:@[
                [caption.topAnchor constraintEqualToAnchor:c.contentView.topAnchor constant:10],
                [caption.leadingAnchor constraintEqualToAnchor:c.contentView.layoutMarginsGuide.leadingAnchor],
                [caption.trailingAnchor constraintEqualToAnchor:c.contentView.layoutMarginsGuide.trailingAnchor],
                [seg.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:6],
                [seg.leadingAnchor constraintEqualToAnchor:c.contentView.layoutMarginsGuide.leadingAnchor],
                [seg.trailingAnchor constraintEqualToAnchor:c.contentView.layoutMarginsGuide.trailingAnchor],
                [seg.bottomAnchor constraintEqualToAnchor:c.contentView.bottomAnchor constant:-10],
                [seg.heightAnchor constraintEqualToConstant:34],
            ]];
            break;
        }
        case VCSectionGeneral: {
            c.textLabel.text = @"Menu điều khiển";
            c.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
            c.imageView.tintColor = [VCTheme accentPink];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.onTintColor = [VCTheme accentPink];
            sw.on = [d boolForKey:kControlMenu];
            [sw addTarget:self action:@selector(controlMenuToggled:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
            break;
        }
        case VCSectionReset: {
            c.textLabel.text = @"Đặt lại cài đặt";
            c.textLabel.textColor = [VCTheme accentRed];
            c.textLabel.textAlignment = NSTextAlignmentCenter;
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
        }
        case VCSectionAbout: {
            if (ip.row == 0) {
                c.textLabel.text = @"Phiên bản";
                c.detailTextLabel.text = [self versionString];
            } else {
                c.textLabel.text = @"Hỗ trợ";
                c.detailTextLabel.text = @"iOS 14 – 17";
            }
            break;
        }
    }
    return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section != VCSectionReset) return;

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Đặt lại cài đặt?"
                                                               message:@"Thao tác này không thể hoàn tác."
                                                        preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Đặt lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [[VCSettingsStore shared] resetToDefaults];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kControlMenu];
        [self.tableView reloadData];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    // iPad cần anchor cho action sheet.
    a.popoverPresentationController.sourceView = [tv cellForRowAtIndexPath:ip];
    a.popoverPresentationController.sourceRect = [tv cellForRowAtIndexPath:ip].bounds;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Actions

- (void)cameraTargetChanged:(UISegmentedControl *)seg {
    [VCSettingsStore shared].cameraTarget = seg.selectedSegmentIndex;
}

- (void)mediaRotationChanged:(UISegmentedControl *)seg {
    static const NSInteger values[] = { -1, 0, 90, 180, 270 };
    NSInteger idx = seg.selectedSegmentIndex;
    if (idx < 0 || idx > 4) return;
    [VCSettingsStore shared].mediaRotation = values[idx];
}

- (void)mediaMirrorToggled:(UISwitch *)sw {
    [VCSettingsStore shared].mediaMirror = sw.on;
}

- (void)rotationOffsetChanged:(UISegmentedControl *)seg {
    static const NSInteger values[] = { 0, 90, 180, 270 };
    NSInteger idx = seg.selectedSegmentIndex;
    if (idx < 0 || idx > 3) return;
    VCSettingsStore *s = [VCSettingsStore shared];
    if (seg.tag == 0) s.rearRotationOffset = values[idx];
    else s.frontRotationOffset = values[idx];
}

- (void)cameraMirrorChanged:(UISegmentedControl *)seg {
    NSInteger idx = seg.selectedSegmentIndex;
    NSInteger value = (idx == 1) ? 0 : (idx == 2) ? 1 : -1;
    VCSettingsStore *s = [VCSettingsStore shared];
    if (seg.tag == 0) s.rearMirror = value;
    else s.frontMirror = value;
}

- (void)reloadTableView {
    [self.tableView reloadData];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)controlMenuToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kControlMenu];
}

@end
