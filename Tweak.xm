#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 日志工具
// =============================================
static void HGLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // 写入文件
    NSString *logPath = @"/var/mobile/Documents/HongGuoLog.txt";
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:@"/var/mobile/Documents"]) {
        [fm createDirectoryAtPath:@"/var/mobile/Documents" withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *timestamp = [NSDate date].description;
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    NSData *data = [logLine dataUsingEncoding:NSUTF8StringEncoding];
    if ([fm fileExistsAtPath:logPath]) {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    } else {
        [data writeToFile:logPath atomically:YES];
    }
    // 同时输出到控制台（方便越狱设备查看）
    NSLog(@"%@", message);
}

// =============================================
// 辅助类：封装所有功能逻辑
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applyTabBarVisibility;
+ (void)applyFullscreen;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
+ (void)dumpViewHierarchy:(UIView *)view prefix:(NSString *)prefix;
@end

@implementation HongGuoHelper

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    HGLog(@"双指长按触发，开始显示设置菜单");
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    HGLog(@"顶层控制器: %@", NSStringFromClass([topVC class]));

    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    HGLog(@"当前设置: fullscreen=%d, hideTab=%d", fullscreen, hideTab);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果设置"
                                                                   message:[NSString stringWithFormat:@"全屏：%@\n隐藏底栏：%@", fullscreen ? @"开" : @"关", hideTab ? @"开" : @"关"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 全屏", fullscreen ? @"关闭" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !fullscreen;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoFullScreen"];
                                                [HongGuoHelper applyFullscreen];
                                                [HongGuoHelper showToast:[NSString stringWithFormat:@"全屏已%@", newVal ? @"开启" : @"关闭"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 底栏", hideTab ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                [HongGuoHelper applyTabBarVisibility];
                                                [HongGuoHelper showToast:[NSString stringWithFormat:@"底栏已%@", newVal ? @"隐藏" : @"显示"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }

    [topVC presentViewController:alert animated:YES completion:nil];
}

+ (void)applyTabBarVisibility {
    HGLog(@"applyTabBarVisibility 被调用");
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject; // 避免 keyWindow 废弃警告
    UIViewController *root = keyWindow.rootViewController;
    HGLog(@"rootViewController: %@", NSStringFromClass([root class]));

    // 诊断：打印整个视图层级
    [self dumpViewHierarchy:keyWindow prefix:@""];

    if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
        UITabBarController *tab = (UITabBarController *)root;
        BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
        HGLog(@"找到 SSTabBarController，设置 tabBar.hidden = %d", hide);
        tab.tabBar.hidden = hide;
        if (hide) {
            tab.tabBar.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.height, 0, 0);
        } else {
            tab.tabBar.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.height - 83, [UIScreen mainScreen].bounds.size.width, 83);
        }
    } else {
        HGLog(@"rootViewController 不是 SSTabBarController，实际类名: %@", NSStringFromClass([root class]));
        // 尝试遍历子控制器
        if ([root isKindOfClass:[UITabBarController class]]) {
            UITabBarController *tab = (UITabBarController *)root;
            HGLog(@"但它是 UITabBarController，尝试操作其 tabBar");
            tab.tabBar.hidden = YES;
        }
    }
}

+ (void)applyFullscreen {
    HGLog(@"applyFullscreen 被调用");
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *root = keyWindow.rootViewController;
    if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
        UITabBarController *tab = (UITabBarController *)root;
        for (UIViewController *vc in tab.viewControllers) {
            HGLog(@"Tab 子控制器: %@", NSStringFromClass([vc class]));
            if ([vc isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) {
                vc.view.frame = [UIScreen mainScreen].bounds;
                HGLog(@"已调整 SSVideoSeriesFeedViewController 的 frame");
            }
        }
    } else {
        HGLog(@"applyFullscreen: root 不是 SSTabBarController");
    }
}

+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

+ (void)dumpViewHierarchy:(UIView *)view prefix:(NSString *)prefix {
    if (!view) return;
    NSString *info = [NSString stringWithFormat:@"%@%@ frame:%@ alpha:%.2f hidden:%d",
                      prefix, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), view.alpha, view.hidden];
    HGLog(@"%@", info);
    for (UIView *sub in view.subviews) {
        [self dumpViewHierarchy:sub prefix:[prefix stringByAppendingString:@"  "]];
    }
}

@end

// =============================================
// Hook UIWindow：添加双指长按手势
// =============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        HGLog(@"UIWindow 初始化，添加双指长按手势");
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
    HGLog(@"双指长按手势触发");
    [HongGuoHelper showSettingsMenuFromWindow:self];
}

%end

// =============================================
// Hook SSTabBarController（如果类存在）
// =============================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    HGLog(@"SSTabBarController viewDidLoad");
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    self.tabBar.hidden = hide;
    if (hide) {
        self.tabBar.frame = CGRectMake(0, self.view.bounds.size.height, 0, 0);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    HGLog(@"SSTabBarController viewWillAppear");
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
    HGLog(@"SSVideoSeriesFeedViewController viewWillAppear");
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
// 构造函数
// =============================================
%ctor {
    HGLog(@"插件加载完成，开始诊断");
    dispatch_async(dispatch_get_main_queue(), ^{
        [HongGuoHelper applyTabBarVisibility];
        [HongGuoHelper applyFullscreen];
        // 额外诊断：打印所有 window
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            HGLog(@"Window: %@", w);
        }
    });
}
