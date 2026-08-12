#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 辅助类：处理设置和遍历视图
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applySettings;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
+ (void)traverseViews:(UIView *)view;
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

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 全屏", fullscreen ? @"关闭" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !fullscreen;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoFullScreen"];
                                                [HongGuoHelper applySettings];
                                                [HongGuoHelper showToast:[NSString stringWithFormat:@"全屏已%@", newVal ? @"开启" : @"关闭"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 底栏", hideTab ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                [HongGuoHelper applySettings];
                                                [HongGuoHelper showToast:[NSString stringWithFormat:@"底栏已%@", newVal ? @"隐藏" : @"显示"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }

    [topVC presentViewController:alert animated:YES completion:nil];
}

+ (void)applySettings {
    // 遍历所有窗口应用设置
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        [self traverseViews:window];
    }
}

+ (void)traverseViews:(UIView *)view {
    if (!view) return;
    
    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];

    // 1. 隐藏底栏：识别 UITabBar 或带 "TabBar" 的类名
    if (hideTab) {
        if ([NSStringFromClass([view class]) rangeOfString:@"TabBar"].location != NSNotFound) {
            view.hidden = YES;
            view.alpha = 0;
            // 也递归子视图
            for (UIView *sub in view.subviews) {
                sub.hidden = YES;
                sub.alpha = 0;
            }
        }
    }

    // 2. 全屏：如果启用，尝试将视图控制器视图扩展到全屏
    if (fullscreen) {
        UIResponder *responder = view;
        while (responder && ![responder isKindOfClass:[UIViewController class]]) {
            responder = [responder nextResponder];
        }
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)responder;
            // 如果是根控制器，且是 TabBarController 类型
            if ([NSStringFromClass([vc class]) rangeOfString:@"TabBarController"].location != NSNotFound) {
                vc.view.frame = [UIScreen mainScreen].bounds;
            }
            // 如果是视频播放控制器（包含 "Video" 或 "Feed"），也设置全屏
            NSString *className = NSStringFromClass([vc class]);
            if ([className rangeOfString:@"Video"].location != NSNotFound ||
                [className rangeOfString:@"Feed"].location != NSNotFound ||
                [className rangeOfString:@"Series"].location != NSNotFound) {
                vc.view.frame = [UIScreen mainScreen].bounds;
            }
        }
    }

    // 递归子视图
    for (UIView *sub in view.subviews) {
        [self traverseViews:sub];
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
// Hook UIViewController：在视图出现后应用设置
// =============================================
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [HongGuoHelper applySettings];
        });
    });
}

- (void)viewWillLayoutSubviews {
    %orig;
    // 每次布局时重新应用（确保全屏生效）
    [HongGuoHelper applySettings];
}

%end

// =============================================
// 构造函数：应用保存的设置
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [HongGuoHelper applySettings];
    });
}
