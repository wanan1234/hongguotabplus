#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 日志工具（限制频率）
// =============================================
static void WriteLog(NSString *format, ...) {
    static NSTimeInterval lastLogTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastLogTime < 0.5) return; // 0.5秒内只记录一次
    lastLogTime = now;

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
// 辅助类：功能函数
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applyTabBarVisibility:(UITabBarController *)tabController;
+ (void)applyFullscreen:(UIViewController *)vc;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
+ (NSString *)logPath;
@end

@implementation HongGuoHelper

+ (NSString *)logPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject] ?: @"/var/mobile/Documents";
    return [documentsDirectory stringByAppendingPathComponent:@"HongGuo.log"];
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
                                                // 手动触发刷新
                                                UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
                                                if (keyWindow) {
                                                    [self applyFullscreen:keyWindow.rootViewController];
                                                }
                                                [self showToast:[NSString stringWithFormat:@"全屏已%@", newVal ? @"开启" : @"关闭"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 底栏", hideTab ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                // 手动触发刷新
                                                UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
                                                if (keyWindow) {
                                                    [self applyTabBarVisibility:(UITabBarController *)keyWindow.rootViewController];
                                                }
                                                [self showToast:[NSString stringWithFormat:@"底栏已%@", newVal ? @"隐藏" : @"显示"] fromWindow:window];
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

+ (void)applyTabBarVisibility:(UITabBarController *)tab {
    if (!tab) {
        WriteLog(@"applyTabBarVisibility: tab is nil");
        return;
    }
    WriteLog(@"applyTabBarVisibility: class=%@", NSStringFromClass([tab class]));

    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    WriteLog(@"hideTabBar = %d", hide);

    // 1. 隐藏/显示 tabBar
    tab.tabBar.hidden = hide;
    if (hide) {
        CGRect frame = tab.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height;
        frame.size.height = 0;
        tab.tabBar.frame = frame;
        WriteLog(@"TabBar hidden, frame set to %@", NSStringFromCGRect(frame));
    } else {
        CGRect frame = tab.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height - 83;
        frame.size.height = 83;
        tab.tabBar.frame = frame;
        WriteLog(@"TabBar shown, frame set to %@", NSStringFromCGRect(frame));
    }

    // 2. 调整根视图全屏
    tab.view.frame = [UIScreen mainScreen].bounds;
    WriteLog(@"Tab view frame set to %@", NSStringFromCGRect(tab.view.frame));

    // 3. 调整内容视图（第一个非 tabBar 的子视图）
    for (UIView *subview in tab.view.subviews) {
        if ([subview isKindOfClass:[UITabBar class]]) continue;
        CGRect frame = subview.frame;
        CGFloat newHeight = tab.view.bounds.size.height - (hide ? 0 : 83);
        if (fabs(frame.size.height - newHeight) > 0.1) {
            frame.size.height = newHeight;
            subview.frame = frame;
            WriteLog(@"Adjusted content view: %@ frame=%@", NSStringFromClass([subview class]), NSStringFromCGRect(frame));
        }
        break;
    }
}

+ (void)applyFullscreen:(UIViewController *)vc {
    if (!vc) {
        WriteLog(@"applyFullscreen: vc is nil");
        return;
    }
    // 只对 SSVideoSeriesFeedViewController 生效
    if (![vc isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) {
        WriteLog(@"applyFullscreen: not SSVideoSeriesFeedViewController, class=%@", NSStringFromClass([vc class]));
        return;
    }

    BOOL full = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (!full) {
        WriteLog(@"applyFullscreen: fullscreen is off");
        return;
    }

    WriteLog(@"applyFullscreen: setting feed view to fullscreen");
    vc.view.frame = [UIScreen mainScreen].bounds;
    if (vc.view.superview) {
        vc.view.superview.frame = [UIScreen mainScreen].bounds;
        WriteLog(@"Superview frame set to fullscreen");
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
// Hook SSTabBarController：在关键生命周期中应用
// =============================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad, applying tab bar visibility");
    [HongGuoHelper applyTabBarVisibility:self];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear, applying tab bar visibility");
    [HongGuoHelper applyTabBarVisibility:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    // 限制频率，由 applyTabBarVisibility 内部已有日志限制，但这里直接调用可能会被日志限流
    // 但仍然调用以保证更新
    [HongGuoHelper applyTabBarVisibility:self];
}

%end

// =============================================
// Hook SSVideoSeriesFeedViewController：应用全屏
// =============================================
%hook SSVideoSeriesFeedViewController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSVideoSeriesFeedViewController viewDidLoad, applying fullscreen");
    [HongGuoHelper applyFullscreen:self];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSVideoSeriesFeedViewController viewWillAppear, applying fullscreen");
    [HongGuoHelper applyFullscreen:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [HongGuoHelper applyFullscreen:self];
}

%end

// =============================================
// 构造函数：初始应用
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        WriteLog(@"HongGuoFullScreen loaded");
        // 延迟应用，确保视图已加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
            if (keyWindow) {
                UIViewController *root = keyWindow.rootViewController;
                Class tabClass = NSClassFromString(@"SSTabBarController");
                if (tabClass && [root isKindOfClass:tabClass]) {
                    [HongGuoHelper applyTabBarVisibility:(UITabBarController *)root];
                }
                // 尝试找到 SSVideoSeriesFeedViewController
                if ([root isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) {
                    [HongGuoHelper applyFullscreen:root];
                } else {
                    // 可能在子控制器中
                    for (UIViewController *child in root.childViewControllers) {
                        if ([child isKindOfClass:NSClassFromString(@"SSVideoSeriesFeedViewController")]) {
                            [HongGuoHelper applyFullscreen:child];
                            break;
                        }
                    }
                }
            }
        });
    });
}
