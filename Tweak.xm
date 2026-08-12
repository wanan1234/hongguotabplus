#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 日志工具（写入 /var/mobile/Documents/，巨魔设备可写）
// =============================================
static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // 同时输出到控制台
    NSLog(@"[HongGuo] %@", msg);

    // 写入文件
    NSString *logPath = @"/var/mobile/Documents/HongGuo.log";
    NSFileManager *fm = [NSFileManager defaultManager];
    // 确保目录存在
    NSString *dir = [logPath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, msg];

    // 追加写入
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

// =============================================
// 辅助类：处理设置和遍历视图
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applySettings;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
+ (void)traverseViews:(UIView *)view depth:(NSInteger)depth;
@end

@implementation HongGuoHelper

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    WriteLog(@"showSettingsMenuFromWindow called");
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
    WriteLog(@"applySettings called");
    // 遍历所有窗口应用设置
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        [self traverseViews:window depth:0];
    }
}

+ (void)traverseViews:(UIView *)view depth:(NSInteger)depth {
    if (!view) return;
    
    // 深度限制，避免过深
    if (depth > 15) return;
    
    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];

    // 记录视图信息（便于调试）
    if (depth == 0) {
        WriteLog(@"Traversing view: %@, frame: %@", NSStringFromClass([view class]), NSStringFromCGRect(view.frame));
    }

    // 1. 隐藏底栏：识别包含 "TabBar" 的类名（不区分大小写）
    if (hideTab) {
        NSString *className = NSStringFromClass([view class]);
        if ([className rangeOfString:@"TabBar" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            WriteLog(@"Hiding TabBar view: %@", className);
            view.hidden = YES;
            view.alpha = 0;
            // 也递归子视图
            for (UIView *sub in view.subviews) {
                sub.hidden = YES;
                sub.alpha = 0;
            }
        }
    }

    // 2. 全屏：尝试将视频视图控制器全屏
    if (fullscreen) {
        // 查找视图所属的视图控制器
        UIResponder *responder = view;
        while (responder && ![responder isKindOfClass:[UIViewController class]]) {
            responder = [responder nextResponder];
        }
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)responder;
            NSString *className = NSStringFromClass([vc class]);
            // 如果控制器包含 Video/Feed/Series，且其视图不是全屏，则设置为全屏
            if ([className rangeOfString:@"Video" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [className rangeOfString:@"Feed" options:NSCaseInsensitiveSearch].location != NSNotFound ||
                [className rangeOfString:@"Series" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                if (!CGRectEqualToRect(vc.view.frame, [UIScreen mainScreen].bounds)) {
                    WriteLog(@"Setting fullscreen for VC: %@", className);
                    vc.view.frame = [UIScreen mainScreen].bounds;
                }
                // 如果视图控制器是导航控制器，也设置其根视图
                if ([vc isKindOfClass:[UINavigationController class]]) {
                    UINavigationController *nav = (UINavigationController *)vc;
                    nav.view.frame = [UIScreen mainScreen].bounds;
                }
            }
        }
    }

    // 递归子视图
    for (UIView *sub in view.subviews) {
        [self traverseViews:sub depth:depth+1];
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
// Hook UIWindow：三指长按手势（避免与FLEX冲突）
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
// Hook UIViewController：在视图出现后应用设置
// =============================================
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WriteLog(@"First viewDidAppear, applying settings");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [HongGuoHelper applySettings];
        });
    });
}

- (void)viewWillLayoutSubviews {
    %orig;
    // 每次布局时重新应用（确保全屏和隐藏生效）
    // 但为了防止频繁调用，限制频率
    static NSTimeInterval lastApplyTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastApplyTime > 0.5) {
        lastApplyTime = now;
        [HongGuoHelper applySettings];
    }
}

%end

// =============================================
// 构造函数：应用保存的设置
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        WriteLog(@"HongGuoFullScreen loaded");
        [HongGuoHelper applySettings];
    });
}
