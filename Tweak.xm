#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// =============================================
// 日志工具（写入 Documents）
// =============================================
static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject] ?: @"/var/mobile/Documents";
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"HongGuo.log"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:documentsDirectory]) {
        [fm createDirectoryAtPath:documentsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, msg];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    NSLog(@"[HongGuo] %@", msg);
}

// =============================================
// 辅助类：核心逻辑基于 DYYY 的做法
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applyTabBarVisibilityForController:(UITabBarController *)tabController;
+ (void)applyFullscreenForController:(UIViewController *)vc;
+ (void)applySettings;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
+ (NSString *)logPath;
+ (UITabBarController *)findTabBarController;
@end

@implementation HongGuoHelper

+ (NSString *)logPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject] ?: @"/var/mobile/Documents";
    return [documentsDirectory stringByAppendingPathComponent:@"HongGuo.log"];
}

+ (UITabBarController *)findTabBarController {
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    UIViewController *root = keyWindow.rootViewController;
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (tabClass && [root isKindOfClass:tabClass]) {
        return (UITabBarController *)root;
    }
    // 检查子控制器
    for (UIViewController *child in root.childViewControllers) {
        if (tabClass && [child isKindOfClass:tabClass]) {
            return (UITabBarController *)child;
        }
    }
    return nil;
}

+ (void)applyTabBarVisibilityForController:(UITabBarController *)tabController {
    if (!tabController) return;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    WriteLog(@"applyTabBarVisibility: hide=%d", hide);

    // 1. 隐藏 tabBar
    tabController.tabBar.hidden = hide;
    if (hide) {
        // 将 tabBar 移出屏幕
        CGRect frame = tabController.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height;
        frame.size.height = 0;
        tabController.tabBar.frame = frame;
    } else {
        // 恢复（假设高度 83）
        CGRect frame = tabController.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height - 83;
        frame.size.height = 83;
        tabController.tabBar.frame = frame;
    }

    // 2. 调整内容视图（第一个非 tabBar 的子视图）
    // 类似于 DYYY 中对 AWENormalModeTabBar 的子视图处理
    for (UIView *subview in tabController.view.subviews) {
        if ([subview isKindOfClass:[UITabBar class]]) continue;
        // 内容容器通常是一个 UIView 或 UIViewControllerWrapperView
        CGRect frame = subview.frame;
        if (hide) {
            frame.size.height = tabController.view.bounds.size.height;
        } else {
            frame.size.height = tabController.view.bounds.size.height - 83;
        }
        subview.frame = frame;
        WriteLog(@"Adjusted content view: %@ frame: %@", NSStringFromClass([subview class]), NSStringFromCGRect(frame));
    }

    // 3. 强制刷新布局
    [tabController.view setNeedsLayout];
    [tabController.view layoutIfNeeded];
}

+ (void)applyFullscreenForController:(UIViewController *)vc {
    if (!vc) return;
    BOOL full = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (!full) return;

    // 检查是否是视频首页控制器
    Class feedClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
    if (![vc isKindOfClass:feedClass]) return;

    WriteLog(@"applyFullscreen for %@", NSStringFromClass([vc class]));

    // 让自身视图全屏
    vc.view.frame = [UIScreen mainScreen].bounds;
    // 如果父视图是 SSTabBarController，确保父视图也全屏
    UITabBarController *tab = [self findTabBarController];
    if (tab) {
        tab.view.frame = [UIScreen mainScreen].bounds;
        // 重新调整 tabBar 和内容视图，确保覆盖
        [self applyTabBarVisibilityForController:tab];
    }
    [vc.view setNeedsLayout];
    [vc.view layoutIfNeeded];
}

+ (void)applySettings {
    WriteLog(@"applySettings called");
    UITabBarController *tab = [self findTabBarController];
    if (tab) {
        [self applyTabBarVisibilityForController:tab];
        // 查找当前选中的视频控制器并应用全屏
        UIViewController *selected = tab.selectedViewController;
        [self applyFullscreenForController:selected];
    } else {
        WriteLog(@"No SSTabBarController found");
    }
}

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    WriteLog(@"showSettingsMenuFromWindow called");
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;

    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果设置"
                                                                   message:[NSString stringWithFormat:@"全屏：%@\n底栏：%@", fullscreen ? @"开" : @"关", hideTab ? @"隐藏" : @"显示"]
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

    [alert addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                NSString *logContent = [NSString stringWithContentsOfFile:[self logPath] encoding:NSUTF8StringEncoding error:nil];
                                                if (!logContent) logContent = @"日志文件不存在或为空";
                                                UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"日志内容" message:logContent preferredStyle:UIAlertControllerStyleAlert];
                                                [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
                                                [topVC presentViewController:logAlert animated:YES completion:nil];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }

    [topVC presentViewController:alert animated:YES completion:nil];
}

+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

@end

// =============================================
// Hook UIWindow：三指长按
// =============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleLongPress:)];
        gesture.numberOfTouchesRequired = 3;
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
        WriteLog(@"UIWindow initialized, added 3-finger gesture");
    }
    return self;
}

%new
- (void)hongguo_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    WriteLog(@"3-finger long press detected");
    [HongGuoHelper showSettingsMenuFromWindow:self];
}

%end

// =============================================
// Hook SSTabBarController
// =============================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    // 应用底栏隐藏
    [HongGuoHelper applyTabBarVisibilityForController:self];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear");
    [HongGuoHelper applyTabBarVisibilityForController:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    // 每次布局时重新应用，确保覆盖任何变化
    [HongGuoHelper applyTabBarVisibilityForController:self];
    // 同时检查全屏
    UIViewController *selected = self.selectedViewController;
    [HongGuoHelper applyFullscreenForController:selected];
}

%end

// =============================================
// Hook SSVideoSeriesFeedViewController
// =============================================
%hook SSVideoSeriesFeedViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSVideoSeriesFeedViewController viewWillAppear");
    [HongGuoHelper applyFullscreenForController:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [HongGuoHelper applyFullscreenForController:self];
}

%end

// =============================================
// 构造函数
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        WriteLog(@"HongGuoFullScreen loaded");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [HongGuoHelper applySettings];
        });
    });
}
