#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// =============================================
// 日志工具（只在关键操作时记录）
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
// 辅助类：核心功能
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applySettings;
+ (void)applyTabBarVisibility:(id)tabController;
+ (void)applyFullscreen:(id)viewController;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
+ (NSString *)logPath;
@end

@implementation HongGuoHelper

+ (NSString *)logPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject] ?: @"/var/mobile/Documents";
    return [documentsDirectory stringByAppendingPathComponent:@"HongGuo.log"];
}

+ (UIViewController *)rootViewController {
    return [UIApplication sharedApplication].windows.firstObject.rootViewController;
}

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    WriteLog(@"showSettingsMenuFromWindow");
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

// ==========================================
// 核心：隐藏底栏（直接操作 tabBar）
// ==========================================
+ (void)applyTabBarVisibility:(id)tabController {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) return;

    UITabBarController *tab = (UITabBarController *)tabController;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    WriteLog(@"applyTabBarVisibility: hide=%d", hide);

    // 1. 隐藏 tabBar
    tab.tabBar.hidden = hide;
    if (hide) {
        CGRect frame = tab.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height;
        frame.size.height = 0;
        tab.tabBar.frame = frame;
    } else {
        CGRect frame = tab.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height - 83;
        frame.size.height = 83;
        tab.tabBar.frame = frame;
    }

    // 2. 调整 tabController 的 view 全屏
    tab.view.frame = [UIScreen mainScreen].bounds;

    // 3. 调整内容容器（第一个非 tabBar 的子视图）
    for (UIView *subview in tab.view.subviews) {
        if ([subview isKindOfClass:[UITabBar class]]) continue;
        CGRect frame = subview.frame;
        frame.size.height = tab.view.bounds.size.height - (hide ? 0 : 83);
        subview.frame = frame;
        WriteLog(@"Adjusted container: %@ frame=%@", NSStringFromClass([subview class]), NSStringFromCGRect(frame));
        break;
    }
}

// ==========================================
// 核心：全屏（只对 SSVideoSeriesFeedViewController）
// ==========================================
+ (void)applyFullscreen:(id)viewController {
    if (!viewController) return;
    if (![viewController isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) return;

    UIViewController *vc = (UIViewController *)viewController;
    BOOL full = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (!full) return;

    WriteLog(@"applyFullscreen: setting feed to fullscreen");
    vc.view.frame = [UIScreen mainScreen].bounds;
    if (vc.view.superview) {
        vc.view.superview.frame = [UIScreen mainScreen].bounds;
    }
}

// ==========================================
// 应用所有设置
// ==========================================
+ (void)applySettings {
    WriteLog(@"applySettings");

    UIViewController *root = [self rootViewController];
    WriteLog(@"root class: %@", NSStringFromClass([root class]));

    // 查找 SSTabBarController
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (!tabClass) {
        WriteLog(@"SSTabBarController class not found");
        return;
    }

    id tabController = nil;
    // 方法1：root 本身就是
    if ([root isKindOfClass:tabClass]) {
        tabController = root;
    }
    // 方法2：遍历子控制器
    if (!tabController) {
        for (UIViewController *child in root.childViewControllers) {
            if ([child isKindOfClass:tabClass]) {
                tabController = child;
                break;
            }
        }
    }
    // 方法3：如果 root 是 UINavigationController，检查栈
    if (!tabController && [root isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)root;
        for (UIViewController *vc in nav.viewControllers) {
            if ([vc isKindOfClass:tabClass]) {
                tabController = vc;
                break;
            }
        }
    }

    if (!tabController) {
        WriteLog(@"SSTabBarController not found");
        return;
    }

    WriteLog(@"Found SSTabBarController: %@", NSStringFromClass([tabController class]));

    // 应用底栏隐藏
    [self applyTabBarVisibility:tabController];

    // 应用全屏：只对当前选中的 SSVideoSeriesFeedViewController
    UITabBarController *tab = (UITabBarController *)tabController;
    UIViewController *selected = tab.selectedViewController;
    WriteLog(@"Selected VC: %@", NSStringFromClass([selected class]));

    if ([selected isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) {
        [self applyFullscreen:selected];
    } else {
        // 遍历所有 tab，找到首页
        for (UIViewController *vc in tab.viewControllers) {
            if ([vc isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) {
                [self applyFullscreen:vc];
                break;
            }
        }
    }
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
    [HongGuoHelper applyTabBarVisibility:self];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear");
    [HongGuoHelper applyTabBarVisibility:self];
}

%end

// =============================================
// Hook SSVideoSeriesFeedViewController
// =============================================
%hook SSVideoSeriesFeedViewController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSVideoSeriesFeedViewController viewDidLoad");
    [HongGuoHelper applyFullscreen:self];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSVideoSeriesFeedViewController viewWillAppear");
    [HongGuoHelper applyFullscreen:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [HongGuoHelper applyFullscreen:self];
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
