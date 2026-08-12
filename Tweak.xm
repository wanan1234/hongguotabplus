#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 双指长按弹出设置菜单（直接 hook UIWindow）
// =============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleLongPress:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
    }
    return self;
}

%new
- (void)hongguo_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    UIViewController *topVC = [self rootViewController];
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果设置"
                                                                   message:[NSString stringWithFormat:@"全屏：%@\n隐藏底栏：%@", fullscreen ? @"开" : @"关", hideTab ? @"开" : @"关"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 全屏", fullscreen ? @"关闭" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !fullscreen;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoFullScreen"];
                                                [self hongguo_applyFullscreen];
                                                [self hongguo_showToast:[NSString stringWithFormat:@"全屏已%@", newVal ? @"开启" : @"关闭"]];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 底栏", hideTab ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                [self hongguo_applyTabBar];
                                                [self hongguo_showToast:[NSString stringWithFormat:@"底栏已%@", newVal ? @"隐藏" : @"显示"]];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 0, 0);
    }

    [topVC presentViewController:alert animated:YES completion:nil];
}

%new
- (void)hongguo_applyTabBar {
    UIViewController *root = [self rootViewController];
    if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
        UITabBarController *tab = (UITabBarController *)root;
        BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
        tab.tabBar.hidden = hide;
        if (hide) {
            tab.tabBar.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.height, 0, 0);
        } else {
            tab.tabBar.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.height - 83, [UIScreen mainScreen].bounds.size.width, 83);
        }
    }
}

%new
- (void)hongguo_applyFullscreen {
    UIViewController *root = [self rootViewController];
    if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
        UITabBarController *tab = (UITabBarController *)root;
        for (UIViewController *vc in tab.viewControllers) {
            if ([vc isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) {
                vc.view.frame = [UIScreen mainScreen].bounds;
            }
        }
    }
}

%new
- (void)hongguo_showToast:(NSString *)msg {
    UIViewController *top = [self rootViewController];
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

%end

// =============================================
// 使用 %group 动态 Hook 红果的类（兼容类不存在的情况）
// =============================================
%group HongGuoGroup

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
    BOOL full = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (full) {
        self.view.frame = [UIScreen mainScreen].bounds;
        if ([self.parentViewController isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
            self.parentViewController.view.frame = [UIScreen mainScreen].bounds;
        }
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    BOOL full = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (full) {
        self.view.frame = [UIScreen mainScreen].bounds;
    }
}

%end

%end // group

%ctor {
    // 动态检测类是否存在，若存在则初始化 group
    if (NSClassFromString(@"SSTabBarController") && NSClassFromString(@"SSVideoSeriesFeedViewController")) {
        %init(HongGuoGroup);
    }
}
