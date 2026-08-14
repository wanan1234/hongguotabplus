// =============================================================
//  HongGuoFullScreen — 精简底栏（只留首页和我的）
//  双指双击弹出菜单 + 详细日志
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
static BOOL isEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoSimplifyTabEnabled"];
}

// ---------- 核心过滤函数 ----------
static void filterTabBarController(UITabBarController *tabController) {
    if (!tabController) {
        WriteLog(@"filterTabBarController: tabController is nil");
        return;
    }
    if (!isEnabled()) {
        WriteLog(@"filterTabBarController: disabled, skip");
        return;
    }

    NSArray *originalVCs = tabController.viewControllers;
    if (!originalVCs || originalVCs.count == 0) {
        WriteLog(@"filterTabBarController: viewControllers empty");
        return;
    }

    WriteLog(@"filterTabBarController: original viewControllers count = %lu", (unsigned long)originalVCs.count);
    for (int i = 0; i < originalVCs.count; i++) {
        UIViewController *vc = originalVCs[i];
        WriteLog(@"  [%d] %@", i, NSStringFromClass([vc class]));
    }

    // 只保留索引0和索引4（如果存在）
    if (originalVCs.count < 5) {
        WriteLog(@"filterTabBarController: less than 5 items, skip");
        return;
    }

    NSMutableArray *filtered = [NSMutableArray array];
    [filtered addObject:originalVCs[0]];
    [filtered addObject:originalVCs[4]];
    WriteLog(@"filterTabBarController: filtered count = %lu", (unsigned long)filtered.count);

    // 应用新的控制器数组
    [tabController setViewControllers:filtered animated:NO];
    [tabController.tabBar setNeedsLayout];
    [tabController.tabBar layoutIfNeeded];
    tabController.selectedIndex = 0;
    WriteLog(@"filterTabBarController: applied successfully");
}

// ---------- 查找并过滤 TabBarController ----------
static void findAndFilterTabBar(UIViewController *root) {
    if (!root) {
        WriteLog(@"findAndFilterTabBar: root is nil");
        return;
    }
    WriteLog(@"findAndFilterTabBar: starting from root class %@", NSStringFromClass([root class]));

    // 如果 root 本身就是 SSTabBarController
    Class tabClass = NSClassFromString(@"SSTabBarController");
    if (tabClass && [root isKindOfClass:tabClass]) {
        WriteLog(@"findAndFilterTabBar: root is SSTabBarController");
        filterTabBarController((UITabBarController *)root);
        return;
    }

    // 遍历子控制器
    for (UIViewController *child in root.childViewControllers) {
        if (tabClass && [child isKindOfClass:tabClass]) {
            WriteLog(@"findAndFilterTabBar: found SSTabBarController in child");
            filterTabBarController((UITabBarController *)child);
            return;
        }
    }

    // 如果 root 是 UINavigationController，检查栈
    if ([root isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)root;
        for (UIViewController *vc in nav.viewControllers) {
            if (tabClass && [vc isKindOfClass:tabClass]) {
                WriteLog(@"findAndFilterTabBar: found SSTabBarController in nav stack");
                filterTabBarController((UITabBarController *)vc);
                return;
            }
        }
    }

    WriteLog(@"findAndFilterTabBar: SSTabBarController NOT found");
}

// ---------- 应用设置 ----------
static void applySettings() {
    WriteLog(@"applySettings called, enabled=%d", isEnabled());
    UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
    if (!keyWindow) {
        WriteLog(@"applySettings: no keyWindow");
        return;
    }
    findAndFilterTabBar(keyWindow.rootViewController);
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

    BOOL enabled = isEnabled();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果精简底栏"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@\n日志路径: Documents/HongGuo.log", enabled ? @"已开启" : @"已关闭"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:enabled ? @"关闭精简" : @"开启精简" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        BOOL newState = !enabled;
        [[NSUserDefaults standardUserDefaults] setBool:newState forKey:@"HongGuoSimplifyTabEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        // 立即应用
        applySettings();
        showToast(newState ? @"精简已开启" : @"精简已关闭", window);
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
        gesture.cancelsTouchesInView = NO;
        [self addGestureRecognizer:gesture];
        WriteLog(@"双指双击手势已添加");
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
// Hook SSTabBarController：在出现时应用
// =============================================================
%hook SSTabBarController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear");
    if (isEnabled()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            filterTabBarController(self);
        });
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewDidAppear");
    if (isEnabled()) {
        // 再次确认，防止被重置
        if (self.viewControllers.count > 2) {
            dispatch_async(dispatch_get_main_queue(), ^{
                filterTabBarController(self);
            });
        }
    }
}
%end

// =============================================================
// Hook SSRootViewController：在根控制器加载时应用
// =============================================================
%hook SSRootViewController
- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSRootViewController viewDidLoad");
    if (isEnabled()) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            applySettings();
        });
    }
}
%end

// =============================================================
// 构造函数
// =============================================================
%ctor {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"HongGuoSimplifyTabEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HongGuoSimplifyTabEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 精简底栏插件加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"开关状态: %@", isEnabled() ? @"开启" : @"关闭");
    WriteLog(@"========================================");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (isEnabled()) {
            applySettings();
        }
    });
}
