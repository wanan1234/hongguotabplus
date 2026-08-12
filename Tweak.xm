#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 日志工具
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
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];

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
// 辅助类
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applySettings;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
@end

@implementation HongGuoHelper

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    WriteLog(@"showSettingsMenuFromWindow");
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;

    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果设置"
                                                                   message:[NSString stringWithFormat:@"底栏：%@", hideTab ? @"已精简" : @"默认"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 精简底栏", hideTab ? @"恢复" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                [HongGuoHelper applySettings];
                                                [HongGuoHelper showToast:[NSString stringWithFormat:@"底栏已%@", newVal ? @"精简" : @"恢复"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                NSString *logPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"HongGuo.log"];
                                                NSString *logContent = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
                                                if (!logContent) logContent = @"日志文件不存在或为空";
                                                UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"日志内容" message:logContent preferredStyle:UIAlertControllerStyleAlert];
                                                [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
                                                [topVC presentViewController:logAlert animated:YES completion:nil];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [topVC presentViewController:alert animated:YES completion:nil];
}

+ (void)applySettings {
    WriteLog(@"applySettings");

    UIViewController *root = [UIApplication sharedApplication].windows.firstObject.rootViewController;
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (!tabClass) {
        WriteLog(@"SSTabBarController class not found");
        return;
    }

    id tabController = nil;
    if ([root isKindOfClass:tabClass]) {
        tabController = root;
    } else {
        for (UIViewController *child in root.childViewControllers) {
            if ([child isKindOfClass:tabClass]) {
                tabController = child;
                break;
            }
        }
        if (!tabController && [root isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nav = (UINavigationController *)root;
            for (UIViewController *vc in nav.viewControllers) {
                if ([vc isKindOfClass:tabClass]) {
                    tabController = vc;
                    break;
                }
            }
        }
    }

    if (!tabController) {
        WriteLog(@"SSTabBarController not found");
        return;
    }

    WriteLog(@"Found SSTabBarController: %@", NSStringFromClass([tabController class]));

    UITabBarController *tab = (UITabBarController *)tabController;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    if (hide) {
        NSArray *originalVCs = tab.viewControllers;
        if (originalVCs.count >= 5) {
            NSMutableArray *filteredVCs = [NSMutableArray array];
            [filteredVCs addObject:originalVCs[0]];
            [filteredVCs addObject:originalVCs[4]];
            tab.viewControllers = filteredVCs;
            
            // 强制刷新 TabBar
            [tab.tabBar setNeedsLayout];
            [tab.tabBar layoutIfNeeded];
            
            // 重新设置选中的索引
            tab.selectedIndex = 0;
            
            WriteLog(@"TabBar精简: 只保留首页和我的");
        } else {
            WriteLog(@"TabBar items count < 5, cannot simplify");
        }
    } else {
        // 恢复模式：提示重启
        WriteLog(@"恢复模式需要重启应用");
        // 可以尝试重新加载原始数据，但无法恢复，所以提示用户
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
        WriteLog(@"UIWindow initialized");
    }
    return self;
}

%new
- (void)hongguo_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    WriteLog(@"3-finger long press");
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
    [HongGuoHelper applySettings];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [HongGuoHelper applySettings];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [HongGuoHelper applySettings];
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
