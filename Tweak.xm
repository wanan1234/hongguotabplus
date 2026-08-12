#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// =============================================
// 诊断工具 - 写入 /tmp/ 确保可写
// =============================================
static void HongGuoWriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // 同时写入 /tmp/ 和 /var/mobile/Documents/
    NSArray *paths = @[@"/tmp/HongGuoDiagnostic.log", @"/var/mobile/Documents/HongGuoDiagnostic.log"];
    for (NSString *path in paths) {
        // 确保目录存在
        NSString *dir = [path stringByDeletingLastPathComponent];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        NSString *timestamp = [df stringFromDate:[NSDate date]];
        NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
        
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) {
            [logLine writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    }
}

static void HongGuoDumpViewHierarchy(UIView *view, NSMutableString *output, NSInteger depth) {
    if (!view) return;
    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    NSString *className = NSStringFromClass([view class]);
    [output appendFormat:@"%@%@ frame:%@ alpha:%.2f hidden:%d\n", indent, className, NSStringFromCGRect(view.frame), view.alpha, view.hidden];
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
    [dump appendString:@"=== Window Hierarchy ===\n"];
    HongGuoDumpViewHierarchy(keyWindow, dump, 0);
    
    [dump appendFormat:@"\n=== Root ViewController ===\n"];
    UIViewController *root = keyWindow.rootViewController;
    [dump appendFormat:@"RootVC: %@\n", root ? NSStringFromClass([root class]) : @"nil"];
    
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (tabClass) {
        [dump appendFormat:@"SSTabBarController class exists: %@\n", tabClass];
        if ([root isKindOfClass:tabClass]) {
            id tab = root;
            [dump appendFormat:@"Root is SSTabBarController\n"];
            id tabBar = [tab valueForKey:@"tabBar"];
            if (tabBar) {
                [dump appendFormat:@"tabBar: %@ frame:%@ hidden:%d\n", NSStringFromClass([tabBar class]), NSStringFromCGRect([tabBar frame]), [tabBar isHidden]];
            } else {
                [dump appendString:@"tabBar is nil\n"];
            }
            NSArray *vcs = [tab valueForKey:@"viewControllers"];
            [dump appendFormat:@"viewControllers count: %lu\n", (unsigned long)vcs.count];
            for (id vc in vcs) {
                [dump appendFormat:@"  %@\n", NSStringFromClass([vc class])];
            }
        } else {
            [dump appendString:@"Root is NOT SSTabBarController\n"];
        }
    } else {
        [dump appendString:@"SSTabBarController class NOT found\n"];
    }
    
    Class feedClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
    if (feedClass) {
        [dump appendFormat:@"SSVideoSeriesFeedViewController class exists: %@\n", feedClass];
    } else {
        [dump appendString:@"SSVideoSeriesFeedViewController class NOT found\n"];
    }
    
    HongGuoWriteLog(@"Diagnostic dump:\n%@", dump);
    NSLog(@"%@", dump);
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
    if (tabClass && [root isKindOfClass:tabClass]) {
        id tab = root;
        id tabBar = [tab valueForKey:@"tabBar"];
        if (tabBar) {
            BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
            [tabBar setValue:@(hide) forKey:@"hidden"];
            if (hide) {
                CGRect frame = [tabBar frame];
                frame.origin.y = [UIScreen mainScreen].bounds.size.height;
                frame.size.height = 0;
                [tabBar setValue:[NSValue valueWithCGRect:frame] forKey:@"frame"];
            } else {
                // 恢复默认（假设高度为83）
                CGRect frame = [tabBar frame];
                frame.origin.y = [UIScreen mainScreen].bounds.size.height - 83;
                frame.size.height = 83;
                [tabBar setValue:[NSValue valueWithCGRect:frame] forKey:@"frame"];
            }
            HongGuoWriteLog(@"TabBar hidden: %d, frame: %@", hide, NSStringFromCGRect([tabBar frame]));
        } else {
            HongGuoWriteLog(@"tabBar is nil");
        }
    } else {
        HongGuoWriteLog(@"Root is not SSTabBarController");
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
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (tabClass && [root isKindOfClass:tabClass]) {
        id tab = root;
        NSArray *vcs = [tab valueForKey:@"viewControllers"];
        Class feedClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
        for (id vc in vcs) {
            if (feedClass && [vc isKindOfClass:feedClass]) {
                UIView *view = [vc valueForKey:@"view"];
                if (view) {
                    view.frame = [UIScreen mainScreen].bounds;
                    HongGuoWriteLog(@"Set feed view frame to fullscreen");
                }
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

@end

// =============================================
// Hook UIWindow 添加手势 - 改为三指长按
// =============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleLongPress:)];
        gesture.numberOfTouchesRequired = 3;  // 改为三指
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
        HongGuoWriteLog(@"UIWindow initialized, added 3-finger long press gesture");
    }
    return self;
}

%new
- (void)hongguo_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    HongGuoWriteLog(@"3-finger long press detected");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"手势触发" message:@"三指长按成功" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [HongGuoHelper showSettingsMenuFromWindow:self];
    }]];
    UIViewController *top = self.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    [top presentViewController:alert animated:YES completion:nil];
}

%end

// =============================================
// 构造函数
// =============================================
%ctor {
    HongGuoWriteLog(@"HongGuoFullScreen loaded - %s", __FILE__);
    dispatch_async(dispatch_get_main_queue(), ^{
        HongGuoWriteLog(@"Running on main queue");
        HongGuoDiagnose();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [HongGuoHelper applyTabBarVisibility];
            [HongGuoHelper applyFullscreen];
        });
    });
}
