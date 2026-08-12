#import <UIKit/UIKit.h>
#import <substrate.h>

static UIViewController *topViewController(UIViewController *root) {
    if (!root) return nil;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    if ([root isKindOfClass:[UINavigationController class]]) {
        return [(UINavigationController *)root topViewController];
    }
    return root;
}

static Class SSTabBarControllerClass;
static Class SSVideoSeriesFeedViewControllerClass;

%ctor {
    SSTabBarControllerClass = NSClassFromString(@"SSTabBarController");
    SSVideoSeriesFeedViewControllerClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
}

%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleDoubleLongPress:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
    }
    return self;
}

%new
- (void)hongguo_handleDoubleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    UIViewController *topVC = topViewController(self.rootViewController);
    if (!topVC) return;
    
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    BOOL hideTabBar = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果全屏设置"
                                                                   message:[NSString stringWithFormat:@"全屏模式: %@\n隐藏底栏: %@", fullscreen ? @"开启" : @"关闭", hideTabBar ? @"开启" : @"关闭"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 全屏模式", fullscreen ? @"关闭" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newValue = !fullscreen;
                                                [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@"HongGuoFullScreen"];
                                                [self hongguo_showToast:[NSString stringWithFormat:@"全屏模式已%@", newValue ? @"开启" : @"关闭"]];
                                            }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 隐藏底栏", hideTabBar ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newValue = !hideTabBar;
                                                [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@"HongGuoHideTabBar"];
                                                [self hongguo_applyTabBarVisibility];
                                                [self hongguo_showToast:[NSString stringWithFormat:@"底栏已%@", newValue ? @"隐藏" : @"显示"]];
                                            }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 0, 0);
    }
    
    [topVC presentViewController:alert animated:YES completion:nil];
}

%new
- (void)hongguo_applyTabBarVisibility {
    UIViewController *root = self.rootViewController;
    if ([root isKindOfClass:SSTabBarControllerClass]) {
        UITabBarController *tabBarController = (UITabBarController *)root;
        BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
        tabBarController.tabBar.hidden = hide;
        if (hide) {
            tabBarController.tabBar.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.height, 0, 0);
        } else {
            // 恢复默认（高度可能不同，简化为隐藏/显示）
            tabBarController.tabBar.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.height - 83, [UIScreen mainScreen].bounds.size.width, 83);
        }
    }
}

%new
- (void)hongguo_showToast:(NSString *)message {
    UIViewController *topVC = topViewController(self.rootViewController);
    if (!topVC) return;
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [topVC presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

%end

%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    self.tabBar.hidden = hide;
    if (hide) {
        self.tabBar.frame = CGRectMake(0, self.view.bounds.size.height, 0, 0);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    self.tabBar.hidden = hide;
    if (hide) {
        self.tabBar.frame = CGRectMake(0, self.view.bounds.size.height, 0, 0);
    }
}

%end

%hook SSVideoSeriesFeedViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (fullscreen) {
        UIViewController *parent = self.parentViewController;
        if ([parent isKindOfClass:SSTabBarControllerClass]) {
            parent.view.frame = [UIScreen mainScreen].bounds;
        }
        self.view.frame = [UIScreen mainScreen].bounds;
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (fullscreen) {
        self.view.frame = [UIScreen mainScreen].bounds;
        UIViewController *parent = self.parentViewController;
        if ([parent isKindOfClass:SSTabBarControllerClass]) {
            parent.view.frame = [UIScreen mainScreen].bounds;
        }
    }
}

%end
