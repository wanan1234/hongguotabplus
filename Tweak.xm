// =============================================================
//  HongGuoFullScreen — 红果短剧 Tab 精简版（KVC 方式，无编译错误）
//  只保留首页和我的，自适应布局，带调试日志
//  双指双击弹出菜单查看日志
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <stdarg.h>

// ---------- 日志工具 ----------
static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
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

// ---------- 开关 ----------
static BOOL HGIsEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreenEnabled"];
}

// ---------- 核心过滤函数（使用 KVC） ----------
static void filterTabBarController(id tabController) {
    if (!tabController) return;
    if (!HGIsEnabled()) return;
    
    // 获取 viewControllers
    NSArray *viewControllers = [tabController valueForKey:@"viewControllers"];
    if (![viewControllers isKindOfClass:[NSArray class]]) {
        WriteLog(@"viewControllers is not an array");
        return;
    }
    
    NSInteger count = viewControllers.count;
    WriteLog(@"viewControllers count: %ld", (long)count);
    
    if (count >= 5) {
        // 保留索引0（首页）和索引4（我的）
        NSArray *filtered = @[viewControllers[0], viewControllers[4]];
        WriteLog(@"Filtered to %@", filtered);
        
        // 设置新的 viewControllers
        [tabController setValue:filtered forKey:@"viewControllers"];
        
        // 获取 tabBar 并刷新布局
        id tabBar = [tabController valueForKey:@"tabBar"];
        if (tabBar) {
            [tabBar performSelector:@selector(setNeedsLayout)];
            [tabBar performSelector:@selector(layoutIfNeeded)];
        }
        
        // 设置选中索引为0
        [tabController setValue:@0 forKey:@"selectedIndex"];
        WriteLog(@"TabBar filtered successfully");
    } else {
        WriteLog(@"viewControllers count < 5, skipping filter");
    }
}

// ---------- 查找并过滤 SSTabBarController ----------
static void findAndFilterTabBarController() {
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    if (!keyWindow) {
        WriteLog(@"No key window found");
        return;
    }
    
    UIViewController *root = keyWindow.rootViewController;
    if (!root) {
        WriteLog(@"No root view controller");
        return;
    }
    
    WriteLog(@"Root class: %@", NSStringFromClass([root class]));
    
    // 查找 SSTabBarController
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (!tabClass) {
        WriteLog(@"SSTabBarController class not found");
        return;
    }
    
    // 尝试从 root 及其子控制器中查找
    UIViewController *tabController = nil;
    if ([root isKindOfClass:tabClass]) {
        tabController = root;
    } else {
        // 遍历子控制器
        for (UIViewController *child in root.childViewControllers) {
            if ([child isKindOfClass:tabClass]) {
                tabController = child;
                break;
            }
        }
        // 如果 root 是 UINavigationController，检查栈
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
        WriteLog(@"SSTabBarController not found in hierarchy");
        return;
    }
    
    WriteLog(@"Found SSTabBarController: %@", NSStringFromClass([tabController class]));
    filterTabBarController(tabController);
}

// =============================================================
// 手势控制（双指双击）
// =============================================================
static void showToast(NSString *msg, UIWindow *window) {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

static void showSettingsMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    
    BOOL enabled = HGIsEnabled();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果设置"
                                                                   message:[NSString stringWithFormat:@"精简Tab: %@", enabled ? @"已开启" : @"已关闭"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:enabled ? @"关闭精简" : @"开启精简" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setBool:!enabled forKey:@"HongGuoFullScreenEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        showToast(@"请重启红果短剧", window);
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths firstObject];
        NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"HongGuo.log"];
        NSString *logContent = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        if (!logContent) logContent = @"日志文件不存在或为空";
        UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"日志内容" message:logContent preferredStyle:UIAlertControllerStyleAlert];
        [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:logAlert animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }
    [topVC presentViewController:alert animated:YES completion:nil];
}

// =============================================================
// Hook UIWindow：双指双击
// =============================================================
%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hg_handleDoubleTap:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.numberOfTapsRequired = 2;
        [self addGestureRecognizer:gesture];
    }
    return self;
}
%new
- (void)hg_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        if (@available(iOS 10.0, *)) {
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
        }
        showSettingsMenu(self);
    }
}
%end

// =============================================================
// Hook 相关控制器，在出现时过滤
// =============================================================

// Hook SSRootViewController，在 viewDidAppear 中查找并过滤
%hook SSRootViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WriteLog(@"SSRootViewController viewDidAppear");
        findAndFilterTabBarController();
    });
}
%end

// 额外 Hook SSTabBarController 自身，确保过滤被执行
%hook SSTabBarController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WriteLog(@"SSTabBarController viewWillAppear");
        filterTabBarController(self);
    });
}
%end

// =============================================================
// 构造函数
// =============================================================
%ctor {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"HongGuoFullScreenEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HongGuoFullScreenEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"精简Tab: %@", HGIsEnabled() ? @"开启" : @"关闭");
    WriteLog(@"========================================");
    
    // 延迟执行，确保视图已加载
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (HGIsEnabled()) {
            findAndFilterTabBarController();
        }
    });
}
