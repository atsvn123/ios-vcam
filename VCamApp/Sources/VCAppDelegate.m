#import "VCAppDelegate.h"
#import "VCTabBarController.h"
#import "VCTheme.h"

@implementation VCAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions {
    [VCTheme applyGlobalAppearance];

    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.backgroundColor = [VCTheme background];
    self.window.tintColor = [VCTheme accentPink];
    self.window.rootViewController = [[VCTabBarController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
