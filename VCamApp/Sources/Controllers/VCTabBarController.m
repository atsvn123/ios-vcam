#import "VCTabBarController.h"
#import "VCSourceViewController.h"
#import "VCLivenessViewController.h"
#import "VCSettingsViewController.h"
#import "VCSettingsStore.h"
#import "VCTheme.h"

static NSString *const kSelectedTab = @"vc.selectedTab";

@interface VCTabBarController () <UITabBarControllerDelegate>
@end

@implementation VCTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.delegate = self;

    UINavigationController *source = [self wrap:[[VCSourceViewController alloc] init]
                                          title:@"Nguồn"
                                          image:@"video"
                                       selected:@"video.fill"];
    UINavigationController *liveness = [self wrap:[[VCLivenessViewController alloc] init]
                                            title:@"Liveness"
                                            image:@"faceid"
                                         selected:@"faceid"];
    UINavigationController *settings = [self wrap:[[VCSettingsViewController alloc] init]
                                            title:@"Settings"
                                            image:@"gearshape"
                                         selected:@"gearshape.fill"];
    self.viewControllers = @[ source, liveness, settings ];

    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:kSelectedTab];
    if (saved >= 0 && saved < (NSInteger)self.viewControllers.count) self.selectedIndex = saved;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsChanged:)
                                                 name:VCSettingsDidChangeNotification
                                               object:nil];
    [self updateLiveBadge];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UINavigationController *)wrap:(UIViewController *)vc
                           title:(NSString *)title
                           image:(NSString *)image
                        selected:(NSString *)selected {
    vc.title = title;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.navigationBar.prefersLargeTitles = YES;
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
                                                   image:[UIImage systemImageNamed:image]
                                           selectedImage:[UIImage systemImageNamed:selected]];
    return nav;
}

- (void)tabBarController:(UITabBarController *)tbc didSelectViewController:(UIViewController *)vc {
    [[NSUserDefaults standardUserDefaults] setInteger:tbc.selectedIndex forKey:kSelectedTab];
}

- (void)settingsChanged:(NSNotification *)note {
    NSString *key = note.userInfo[@"key"];
    if ([key isEqualToString:@"live"] || [key isEqualToString:@"*"]) [self updateLiveBadge];
}

/// Chấm "LIVE" trên tab Nguồn để thấy trạng thái khi đang ở tab khác.
- (void)updateLiveBadge {
    UITabBarItem *item = self.viewControllers.firstObject.tabBarItem;
    if ([VCSettingsStore shared].isLive) {
        item.badgeValue = @"LIVE";
        item.badgeColor = [VCTheme liveGreen];
    } else {
        item.badgeValue = nil;
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }

@end
