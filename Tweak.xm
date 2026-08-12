#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// =============================================
// 日志工具（写入 Documents，带节流）
// =============================================
static NSMutableSet *loggedMessages = nil;
static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // 只记录新消息（避免重复）
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loggedMessages = [NSMutableSet set];
    });
    if ([loggedMessages containsObject:msg]) return;
    [loggedMessages addObject:msg];

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
// 辅助类：直接操作 TabBarController 和视频控制器
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applyTabBarVisibility:(UITabBarController *)tab;
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
                                                // 刷新全屏
                                                UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
                                                UIViewController *root = keyWindow.rootViewController;
                                                if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
                                                    UITabBarController *tab = (UITabBarController *)root;
                                                    UIViewController *selected = tab.selectedViewController;
                                                    [self applyFullscreen:selected];
                                                }
                                                [self showToast:[NSString stringWithFormat:@"全屏已%@", newVal ? @"开启" : @"关闭"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 底栏", hideTab ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                // 刷新底栏
                                                UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
                                                UIViewController *root = keyWindow.rootViewController;
                                                if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
                                                    [self applyTabBarVisibility:(UITabBarController *)root];
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
    if (!tab) return;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    WriteLog(@"applyTabBarVisibility: hide=%d", hide);

    // 隐藏/显示 tabBar
    tab.tabBar.hidden = hide;
    if (hide) {
        // 移出屏幕
        CGRect frame = tab.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height;
        frame.size.height = 0;
        tab.tabBar.frame = frame;
    } else {
        // 恢复默认（假设高度 83）
        CGRect frame = tab.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height - 83;
        frame.size.height = 83;
        tab.tabBar.frame = frame;
    }

    // 调整根视图高度，填满屏幕
    tab.view.frame = [UIScreen mainScreen].bounds;

    // 调整内容视图（第一个非 tabBar 的子视图）
    for (UIView *subview in tab.view.subviews) {
        if ([subview isKindOfClass:[UITabBar class]]) continue;
        CGRect frame = subview.frame;
        frame.size.height = tab.view.bounds.size.height - (hide ? 0 : 83);
        subview.frame = frame;
    }
}

+ (void)applyFullscreen:(UIViewController *)vc {
    if (!vc) return;
    BOOL full = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    WriteLog(@"applyFullscreen: vc=%@, full=%d", NSStringFromClass([vc class]), full);

    if (full) {
        // 只对视频控制器做全屏（通过类名判断）
        NSString *className = NSStringFromClass([vc class]);
        if ([className isEqualToString:@"SSVideoSeriesFeedViewController"] ||
            [className isEqualToString:@"SSVideoFeedContainerViewController"] ||
            [className isEqualToString:@"FQVShortVideoListViewController"]) {
            vc.view.frame = [UIScreen mainScreen].bounds;
            // 如果父视图存在，也调整
            if (vc.view.superview) {
                vc.view.superview.frame = [UIScreen mainScreen].bounds;
            }
            WriteLog(@"Fullscreen applied to: %@", className);
        } else {
            WriteLog(@"Skipping fullscreen for non-video VC: %@", className);
        }
    } else {
        // 恢复默认（由系统控制，但我们可以重置为合理大小）
        // 这里不主动恢复，因为系统会重新布局
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
        WriteLog(@"UIWindow initialized with 3-finger gesture");
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
// Hook SSTabBarController：控制底栏隐藏
// =============================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    // 由于 SSTabBarController 继承自 UITabBarController，我们可以安全地将其视为 UITabBarController
    [HongGuoHelper applyTabBarVisibility:(UITabBarController *)self];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear");
    [HongGuoHelper applyTabBarVisibility:(UITabBarController *)self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    // 每次布局时重新应用，但限制日志频率
    static NSTimeInterval lastApplyTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastApplyTime > 0.5) { // 0.5秒内只执行一次
        lastApplyTime = now;
        [HongGuoHelper applyTabBarVisibility:(UITabBarController *)self];
    }
}

%end

// =============================================
// Hook SSVideoSeriesFeedViewController：全屏控制
// =============================================
%hook SSVideoSeriesFeedViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSVideoSeriesFeedViewController viewWillAppear");
    [HongGuoHelper applyFullscreen:self];
}

- (void)viewDidLayoutSubviews {
    %orig;
    static NSTimeInterval lastApplyTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastApplyTime > 0.5) {
        lastApplyTime = now;
        [HongGuoHelper applyFullscreen:self];
    }
}

%end

// =============================================
// 构造函数：首次加载时应用设置
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        WriteLog(@"HongGuoFullScreen loaded");
        // 延迟应用，确保视图已加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
            UIViewController *root = keyWindow.rootViewController;
            if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
                [HongGuoHelper applyTabBarVisibility:(UITabBarController *)root];
                UIViewController *selected = [(UITabBarController *)root selectedViewController];
                [HongGuoHelper applyFullscreen:selected];
            }
        });
    });
}
