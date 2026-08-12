#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 日志工具（直接写入 /tmp，确保可写）
// =============================================
static void WriteLog(const char *format, ...) {
    va_list args;
    va_start(args, format);
    char *msg = NULL;
    vasprintf(&msg, format, args);
    va_end(args);
    if (!msg) return;

    // 同时输出到控制台
    NSLog(@"%s", msg);

    // 写入文件
    FILE *fp = fopen("/tmp/HongGuo.log", "a");
    if (fp) {
        time_t now = time(NULL);
        struct tm *tm_info = localtime(&now);
        char time_str[64];
        strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);
        fprintf(fp, "[%s] %s\n", time_str, msg);
        fflush(fp);
        fclose(fp);
    }
    free(msg);
}

// =============================================
// 辅助类：封装功能（使用运行时动态获取类）
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applyTabBarVisibility;
+ (void)applyFullscreen;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
@end

@implementation HongGuoHelper

+ (UIViewController *)rootViewController {
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    return keyWindow.rootViewController;
}

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    WriteLog("showSettingsMenuFromWindow");
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
    WriteLog("applyTabBarVisibility");
    UIViewController *root = [self rootViewController];
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (!tabClass || ![root isKindOfClass:tabClass]) {
        WriteLog("Root is not SSTabBarController, actual: %s", NSStringFromClass([root class]).UTF8String);
        return;
    }

    // 强制转为 UITabBarController（因为 SSTabBarController 继承自它）
    UITabBarController *tab = (UITabBarController *)root;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    // 隐藏/显示 tabBar
    tab.tabBar.hidden = hide;
    if (hide) {
        // 将 tabBar 移出屏幕
        CGRect frame = tab.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height;
        frame.size.height = 0;
        tab.tabBar.frame = frame;
    } else {
        // 恢复（假设默认高度 83）
        CGRect frame = tab.tabBar.frame;
        frame.origin.y = [UIScreen mainScreen].bounds.size.height - 83;
        frame.size.height = 83;
        tab.tabBar.frame = frame;
    }

    // 调整根视图高度
    tab.view.frame = [UIScreen mainScreen].bounds;

    // 调整内容视图（第一个非 tabBar 的子视图）
    for (UIView *subview in tab.view.subviews) {
        if ([subview isKindOfClass:[UITabBar class]]) continue;
        CGRect frame = subview.frame;
        frame.size.height = tab.view.bounds.size.height - (hide ? 0 : 83);
        subview.frame = frame;
    }

    WriteLog("TabBar hidden: %d", hide);
}

+ (void)applyFullscreen {
    WriteLog("applyFullscreen");
    UIViewController *root = [self rootViewController];
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (!tabClass || ![root isKindOfClass:tabClass]) return;

    UITabBarController *tab = (UITabBarController *)root;
    UIViewController *selected = tab.selectedViewController;
    Class feedClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
    if (feedClass && [selected isKindOfClass:feedClass]) {
        selected.view.frame = [UIScreen mainScreen].bounds;
        WriteLog("Feed view set to fullscreen");
    } else {
        WriteLog("Selected is not SSVideoSeriesFeedViewController: %s", NSStringFromClass([selected class]).UTF8String);
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
// Hook UIWindow：三指长按手势
// =============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleLongPress:)];
        gesture.numberOfTouchesRequired = 3;
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
        WriteLog("UIWindow initialized, added 3-finger gesture");
    }
    return self;
}

%new
- (void)hongguo_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    WriteLog("3-finger long press detected");
    [HongGuoHelper showSettingsMenuFromWindow:self];
}

%end

// =============================================
// 构造函数：应用保存的设置
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        WriteLog("HongGuoFullScreen loaded");
        // 延迟执行，确保界面已加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [HongGuoHelper applyTabBarVisibility];
            [HongGuoHelper applyFullscreen];
        });
    });
}
