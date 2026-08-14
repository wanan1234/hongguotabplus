// =============================================================
//  HongGuoFullScreen — 诊断版（只保留首页和我的Tab）
//  双指双击弹出菜单，可查看日志
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

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

static BOOL gApplied = NO;

// ---------- 执行过滤 ----------
static void filterTabBarController(UIViewController *controller) {
    if (![controller isKindOfClass:[UITabBarController class]]) {
        WriteLog(@"Controller is not UITabBarController: %@", NSStringFromClass([controller class]));
        return;
    }
    UITabBarController *tab = (UITabBarController *)controller;
    NSArray *originalVCs = tab.viewControllers;
    if (originalVCs.count < 5) {
        WriteLog(@"viewControllers count < 5: %lu, skip filtering", (unsigned long)originalVCs.count);
        return;
    }
    WriteLog(@"Filtering tab bar, original count: %lu", (unsigned long)originalVCs.count);
    NSMutableArray *filtered = [NSMutableArray array];
    [filtered addObject:originalVCs[0]];
    [filtered addObject:originalVCs[4]];
    // 注意：保留的控制器需要保留它们的 tabBarItem，系统会自动复制
    [tab setViewControllers:filtered animated:NO];
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    tab.selectedIndex = 0;
    WriteLog(@"Filtered to %lu items, selectedIndex=0", (unsigned long)filtered.count);
    gApplied = YES;
}

// =============================================================
// Hook UIWindow：双指双击手势（用于查看日志）
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

static void showDiagnosticMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果诊断"
                                                                   message:@"点击查看日志"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
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

%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hg_handleDoubleTap:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.numberOfTapsRequired = 2;
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
        showDiagnosticMenu(self);
    }
}
%end

// =============================================================
// Hook SSTabBarController（当作 UITabBarController 处理）
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad called");
    if (!gApplied) {
        // 在这里也尝试过滤，但可能太早，需要延迟
        dispatch_async(dispatch_get_main_queue(), ^{
            filterTabBarController(self);
        });
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear called");
    if (!gApplied) {
        filterTabBarController(self);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewDidAppear called");
    if (!gApplied) {
        // 再次尝试，确保生效
        filterTabBarController(self);
    }
}

// 监控 selectedIndex 变化，记录日志
- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    %orig;
    WriteLog(@"selectedIndex changed to: %lu", (unsigned long)selectedIndex);
    // 打印当前 viewControllers 信息
    if ([self isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)self;
        NSArray *vcs = tab.viewControllers;
        if (vcs.count > 0 && selectedIndex < vcs.count) {
            UIViewController *vc = vcs[selectedIndex];
            WriteLog(@"Current selected VC: %@", NSStringFromClass([vc class]));
        }
    }
}

%end

// =============================================================
// Hook UITabBarItem 点击（诊断）
// =============================================================
// 我们无法直接 Hook 点击事件，但可以 Hook UITabBar 的 setItems 来记录
%hook UITabBar
- (void)setItems:(NSArray<UITabBarItem *> *)items animated:(BOOL)animated {
    WriteLog(@"UITabBar setItems called with %lu items", (unsigned long)items.count);
    for (UITabBarItem *item in items) {
        WriteLog(@"  item title: %@", item.title);
    }
    %orig;
}
%end

// =============================================================
// 构造函数
// =============================================================
%ctor {
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 诊断版加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
    // 延迟执行一次，在应用启动后尝试过滤
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) {
            WriteLog(@"No keyWindow found");
            return;
        }
        UIViewController *root = keyWindow.rootViewController;
        // 查找 SSTabBarController
        Class tabClass = NSClassFromString(@"SSTabBarController");
        if (!tabClass) {
            WriteLog(@"SSTabBarController class not found");
            return;
        }
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
        }
        if (tabController) {
            WriteLog(@"Found SSTabBarController: %@", NSStringFromClass([tabController class]));
            filterTabBarController(tabController);
        } else {
            WriteLog(@"SSTabBarController not found in root hierarchy");
        }
    });
}
