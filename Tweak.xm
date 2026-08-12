#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 辅助类：封装所有功能逻辑（纯 Objective-C）
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applyTabBarVisibility;
+ (void)applyFullscreen;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
@end

@implementation HongGuoHelper

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果设置"
                                                                   message:[NSString stringWithFormat:@"全屏：%@\n隐藏底栏：%@", fullscreen ? @"开" : @"关", hideTab ? @"开" : @"关"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    // 切换全屏
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 全屏", fullscreen ? @"关闭" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !fullscreen;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoFullScreen"];
                                                [HongGuoHelper applyFullscreen];
                                                [HongGuoHelper showToast:[NSString stringWithFormat:@"全屏已%@", newVal ? @"开启" : @"关闭"] fromWindow:window];
                                            }]];

    // 切换隐藏底栏
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 底栏", hideTab ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                [HongGuoHelper applyTabBarVisibility];
                                                [HongGuoHelper showToast:[NSString stringWithFormat:@"底栏已%@", newVal ? @"隐藏" : @"显示"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    // iPad 适配
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }

    [topVC presentViewController:alert animated:YES completion:nil];
}

+ (void)applyTabBarVisibility {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    UIViewController *root = keyWindow.rootViewController;
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

+ (void)applyFullscreen {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    UIViewController *root = keyWindow.rootViewController;
    if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
        UITabBarController *tab = (UITabBarController *)root;
        for (UIViewController *vc in tab.viewControllers) {
            if ([vc isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) {
                vc.view.frame = [UIScreen mainScreen].bounds;
            }
        }
    }
}

+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

@end

// =============================================
// Hook UIWindow：添加双指长按手势
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
    [HongGuoHelper showSettingsMenuFromWindow:self];
}

%end

// =============================================
// Hook SSTabBarController（如果类存在）
// =============================================
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

// =============================================
// Hook SSVideoSeriesFeedViewController（如果类存在）
// =============================================
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

// =============================================
// 构造函数：应用保存的设置（无需 %init）
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [HongGuoHelper applyTabBarVisibility];
        [HongGuoHelper applyFullscreen];
    });
}
