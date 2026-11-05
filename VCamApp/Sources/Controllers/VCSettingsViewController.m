#import "VCSettingsViewController.h"
#import "VCSettingsStore.h"
#import "VCTheme.h"

static NSString *const kCameraTarget = @"vc.cameraTarget";   // 0 cả hai, 1 cam sau, 2 cam trước
static NSString *const kControlMenu  = @"vc.controlMenu";    // nút nổi trong app khác

typedef NS_ENUM(NSInteger, VCSection) {
    VCSectionCamera = 0,
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
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ kCameraTarget: @0, kControlMenu: @NO }];
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
        case VCSectionGeneral: return 1;
        case VCSectionReset:   return 1;
        case VCSectionAbout:   return 2;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case VCSectionCamera:  return @"Camera bị fake";
        case VCSectionGeneral: return @"Chung";
        case VCSectionAbout:   return @"Thông tin";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case VCSectionCamera:  return @"Chọn camera sẽ bị thay bằng nguồn VCam.";
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
            NSInteger v = [d integerForKey:kCameraTarget];
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
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d removeObjectForKey:kCameraTarget];
        [d removeObjectForKey:kControlMenu];
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
    [[NSUserDefaults standardUserDefaults] setInteger:seg.selectedSegmentIndex forKey:kCameraTarget];
}

- (void)controlMenuToggled:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kControlMenu];
}

@end
