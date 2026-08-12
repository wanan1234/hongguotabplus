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
// 辅助类：功能实现（基于递归遍历）
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applySettings;
+ (void)traverseViews:(UIView *)view depth:(NSInteger)depth;
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

+ (void)applySettings {
    WriteLog(@"applySettings called");
    // 遍历所有窗口
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        [self traverseViews:window depth:0];
    }
}

+ (void)traverseViews:(UIView *)view depth:(NSInteger)depth {
    if (!view) return;
    
    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];

    NSString *className = NSStringFromClass([view class]);
    
    // ==========================================
    // 1. 隐藏底栏相关视图（包括背景）
    // ==========================================
    if (hideTab) {
        // 隐藏所有包含 "TabBar" 的视图
        if ([className rangeOfString:@"TabBar"].location != NSNotFound) {
            WriteLog(@"Hiding TabBar view: %@", className);
            view.hidden = YES;
            view.alpha = 0;
            for (UIView *sub in view.subviews) {
                sub.hidden = YES;
                sub.alpha = 0;
            }
        }
        
        // 隐藏底栏背景（_UIBarBackground 或类似的）
        if ([className isEqualToString:@"_UIBarBackground"] || 
            [className rangeOfString:@"BarBackground"].location != NSNotFound) {
            WriteLog(@"Hiding background view: %@", className);
            view.hidden = YES;
            view.alpha = 0;
        }
        
        // 隐藏可能的占位容器（高度接近 tabBar 高度的视图）
        if (view.frame.size.height > 40 && view.frame.size.height < 100) {
            // 检查它是不是在底部
            CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
            if (view.frame.origin.y + view.frame.size.height >= screenHeight - 10) {
                WriteLog(@"Hiding bottom view: %@ frame: %@", className, NSStringFromCGRect(view.frame));
                view.hidden = YES;
                view.alpha = 0;
            }
        }
    }

    // ==========================================
    // 2. 全屏：只对视频播放相关的视图控制器生效
    // ==========================================
    if (fullscreen) {
        // 向上查找视图控制器
        UIResponder *responder = view;
        while (responder && ![responder isKindOfClass:[UIViewController class]]) {
            responder = [responder nextResponder];
        }
        
        if ([responder isKindOfClass:[UIViewController class]]) {
            UIViewController *vc = (UIViewController *)responder;
            NSString *vcClassName = NSStringFromClass([vc class]);
            
            // 只对特定的视频/Feed 控制器做全屏（避免侧边栏被全屏）
            BOOL isVideoController = 
                [vcClassName rangeOfString:@"Video"].location != NSNotFound ||
                [vcClassName rangeOfString:@"Feed"].location != NSNotFound ||
                [vcClassName rangeOfString:@"Series"].location != NSNotFound;
            
            // 排除侧边栏/抽屉控制器
            BOOL isSidebarController = 
                [vcClassName rangeOfString:@"Sidebar"].location != NSNotFound ||
                [vcClassName rangeOfString:@"Drawer"].location != NSNotFound ||
                [vcClassName rangeOfString:@"Menu"].location != NSNotFound;
            
            if (isVideoController && !isSidebarController && vc.view) {
                WriteLog(@"Setting fullscreen for: %@", vcClassName);
                vc.view.frame = [UIScreen mainScreen].bounds;
            }
        }
        
        // 对于视图本身，如果它是视频播放器视图，也设置全屏
        if ([className rangeOfString:@"Player"].location != NSNotFound ||
            [className rangeOfString:@"VideoView"].location != NSNotFound ||
            [className rangeOfString:@"RenderView"].location != NSNotFound) {
            WriteLog(@"Setting fullscreen for view: %@", className);
            view.frame = [UIScreen mainScreen].bounds;
        }
    }

    // ==========================================
    // 3. 递归遍历子视图
    // ==========================================
    for (UIView *sub in view.subviews) {
        [self traverseViews:sub depth:depth + 1];
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
// Hook UIViewController：视图出现时应用设置
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
    // 每次布局时重新应用（确保全屏/隐藏生效）
    static NSTimeInterval lastApplyTime = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastApplyTime > 0.1) { // 限流，避免频繁调用
        lastApplyTime = now;
        [HongGuoHelper applySettings];
    }
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
