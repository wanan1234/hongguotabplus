#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>

// =============================================
// 诊断日志（写入 /var/mobile/Documents/HongGuoDiagnostic.log）
// =============================================
static void HongGuoWriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSString *logPath = @"/var/mobile/Documents/HongGuoDiagnostic.log";
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:@"/var/mobile/Documents"]) {
        [fm createDirectoryAtPath:@"/var/mobile/Documents" withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    // 追加到文件
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [logLine writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

static void HongGuoDumpViewHierarchy(UIView *view, NSMutableString *output, NSInteger depth) {
    if (!view) return;
    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    NSString *className = NSStringFromClass([view class]);
    [output appendFormat:@"%@%@ frame:%@ alpha:%.2f hidden:%d userInteraction:%d\n", indent, className, NSStringFromCGRect(view.frame), view.alpha, view.hidden, view.userInteractionEnabled];
    for (UIView *sub in view.subviews) {
        HongGuoDumpViewHierarchy(sub, output, depth+1);
    }
}

static void HongGuoDiagnose() {
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    if (!keyWindow) {
        HongGuoWriteLog(@"No key window found");
        return;
    }
    NSMutableString *dump = [NSMutableString string];
    [dump appendString:@"=== Windows ===\n"];
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *w in windows) {
        [dump appendFormat:@"Window: %@ frame:%@ hidden:%d\n", NSStringFromClass([w class]), NSStringFromCGRect(w.frame), w.hidden];
    }
    [dump appendFormat:@"\n=== Key Window Hierarchy ===\n"];
    HongGuoDumpViewHierarchy(keyWindow, dump, 0);
    
    [dump appendFormat:@"\n=== Root ViewController ===\n"];
    UIViewController *root = keyWindow.rootViewController;
    [dump appendFormat:@"RootVC: %@\n", root ? NSStringFromClass([root class]) : @"nil"];
    if (root) {
        [dump appendFormat:@"Child VCs: %lu\n", (unsigned long)root.childViewControllers.count];
        for (UIViewController *vc in root.childViewControllers) {
            [dump appendFormat:@"  %@\n", NSStringFromClass([vc class])];
        }
        if (root.presentedViewController) {
            [dump appendFormat:@"Presented: %@\n", NSStringFromClass([root.presentedViewController class])];
        }
    }
    
    // 查找 SSTabBarController
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (tabClass) {
        [dump appendFormat:@"\nSSTabBarController class exists: %@\n", tabClass];
        id tab = nil;
        UIViewController *current = root;
        while (current) {
            if ([current isKindOfClass:tabClass]) {
                tab = current;
                break;
            }
            if (current.childViewControllers.count > 0) {
                current = current.childViewControllers.firstObject;
            } else {
                break;
            }
        }
        if (tab) {
            [dump appendFormat:@"Found SSTabBarController: %@\n", tab];
            id tabBar = [tab valueForKey:@"tabBar"];
            if (tabBar) {
                [dump appendFormat:@"tabBar: %@ frame:%@ hidden:%d\n", NSStringFromClass([tabBar class]), NSStringFromCGRect([tabBar frame]), [tabBar isHidden]];
                // 列出所有子视图
                for (UIView *sub in [tabBar subviews]) {
                    [dump appendFormat:@"  tabBar subview: %@ frame:%@\n", NSStringFromClass([sub class]), NSStringFromCGRect(sub.frame)];
                }
            } else {
                [dump appendString:@"tabBar is nil\n"];
            }
            NSArray *vcs = [tab valueForKey:@"viewControllers"];
            if (vcs) {
                [dump appendFormat:@"viewControllers count: %lu\n", (unsigned long)vcs.count];
                for (id vc in vcs) {
                    [dump appendFormat:@"  %@\n", NSStringFromClass([vc class])];
                }
            }
        } else {
            [dump appendString:@"SSTabBarController not found in hierarchy\n"];
        }
    } else {
        [dump appendString:@"SSTabBarController class NOT found\n"];
    }
    
    // 查找首页控制器
    Class feedClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
    if (feedClass) {
        [dump appendFormat:@"\nSSVideoSeriesFeedViewController class exists: %@\n", feedClass];
    } else {
        [dump appendString:@"SSVideoSeriesFeedViewController class NOT found\n"];
    }
    
    HongGuoWriteLog(@"Diagnostic dump:\n%@", dump);
}

// =============================================
// 辅助类
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applyTabBarVisibility;
+ (void)applyFullscreen;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
@end

@implementation HongGuoHelper

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    HongGuoWriteLog(@"showSettingsMenuFromWindow called");
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
    HongGuoWriteLog(@"applyTabBarVisibility");
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    if (!keyWindow) {
        HongGuoWriteLog(@"No window");
        return;
    }
    UIViewController *root = keyWindow.rootViewController;
    Class tabClass = NSClassFromString(@"SSTabBarController");
    id tab = nil;
    UIViewController *current = root;
    while (current) {
        if ([current isKindOfClass:tabClass]) {
            tab = current;
            break;
        }
        if (current.childViewControllers.count > 0) {
            current = current.childViewControllers.firstObject;
        } else {
            break;
        }
    }
    if (tab) {
        id tabBar = [tab valueForKey:@"tabBar"];
        if (tabBar) {
            BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
            // 直接隐藏整个 tabBar
            [tabBar setValue:@(hide) forKey:@"hidden"];
            if (hide) {
                // 将 tabBar 移出屏幕
                CGRect frame = [tabBar frame];
                frame.origin.y = [UIScreen mainScreen].bounds.size.height;
                frame.size.height = 0;
                [tabBar setValue:[NSValue valueWithCGRect:frame] forKey:@"frame"];
            } else {
                // 恢复默认位置
                CGRect frame = [tabBar frame];
                frame.origin.y = [UIScreen mainScreen].bounds.size.height - 83;  // 估计高度
                frame.size.height = 83;
                [tabBar setValue:[NSValue valueWithCGRect:frame] forKey:@"frame"];
            }
            HongGuoWriteLog(@"TabBar hidden: %d, frame: %@", hide, NSStringFromCGRect([tabBar frame]));
        } else {
            HongGuoWriteLog(@"tabBar is nil");
        }
    } else {
        HongGuoWriteLog(@"SSTabBarController not found");
    }
}

+ (void)applyFullscreen {
    HongGuoWriteLog(@"applyFullscreen");
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    if (!keyWindow) {
        HongGuoWriteLog(@"No window");
        return;
    }
    UIViewController *root = keyWindow.rootViewController;
    // 找到当前显示的控制器（可能是导航控制器中的首页）
    UIViewController *topVC = root;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    if ([topVC isKindOfClass:[UINavigationController class]]) {
        topVC = [(UINavigationController *)topVC topViewController];
    }
    // 如果是首页控制器，全屏其 view
    Class feedClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
    if (feedClass && [topVC isKindOfClass:feedClass]) {
        topVC.view.frame = [UIScreen mainScreen].bounds;
        HongGuoWriteLog(@"Set feed view frame to fullscreen");
    } else {
        HongGuoWriteLog(@"Top VC is not feed: %@", NSStringFromClass([topVC class]));
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

@end

// =============================================
// Hook UIWindow 添加手势（三指）
// =============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        // 改为三指长按（避免与 FLEX 冲突）
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleLongPress:)];
        gesture.numberOfTouchesRequired = 3;
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
        HongGuoWriteLog(@"UIWindow initialized, added 3-finger gesture");
    }
    return self;
}

%new
- (void)hongguo_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    HongGuoWriteLog(@"3-finger long press detected");
    // 显示诊断日志已生成
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"手势触发" message:@"正在生成诊断日志..." preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *top = self.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    [top presentViewController:alert animated:YES completion:^{
        // 执行诊断
        HongGuoDiagnose();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                // 然后打开设置菜单
                [HongGuoHelper showSettingsMenuFromWindow:self];
            }];
        });
    }];
}

%end

// =============================================
// 构造函数
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        HongGuoWriteLog(@"HongGuoFullScreen loaded");
        // 延迟一下再诊断，确保视图完全加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            HongGuoDiagnose();
            [HongGuoHelper applyTabBarVisibility];
            [HongGuoHelper applyFullscreen];
        });
    });
}
