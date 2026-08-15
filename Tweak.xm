// =============================================================
//  HongGuoFullScreen — 诊断版（只输出日志，不修复）
//  用于定位黑块的根本原因
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <stdarg.h>

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
    NSLog(@"[HongGuo-Diag] %@", msg);
}

static BOOL isEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreenEnabled"];
}

static NSInteger defaultTabIndex() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"HongGuoDefaultTab"];
}

static NSInteger indexOfMyVC(NSArray *vcs) {
    for (NSInteger i = 0; i < vcs.count; i++) {
        UIViewController *vc = vcs[i];
        NSString *title = vc.tabBarItem.title;
        if ([title isEqualToString:@"我的"]) {
            return i;
        }
    }
    return -1;
}

// 辅助函数：打印视图的详细背景信息
static void logViewBackground(UIView *view, NSString *label) {
    if (!view) {
        WriteLog(@"  %@: view is nil", label);
        return;
    }
    WriteLog(@"  %@: %@", label, NSStringFromClass([view class]));
    WriteLog(@"    frame: %@", NSStringFromCGRect(view.frame));
    WriteLog(@"    backgroundColor: %@", view.backgroundColor ?: @"nil");
    WriteLog(@"    hidden: %d, alpha: %.2f", view.hidden, view.alpha);
    WriteLog(@"    layer.backgroundColor: %@", view.layer.backgroundColor ? [UIColor colorWithCGColor:view.layer.backgroundColor] : @"nil");
    WriteLog(@"    layer.cornerRadius: %.2f, masksToBounds: %d", view.layer.cornerRadius, view.layer.masksToBounds);
    if ([view isKindOfClass:[UITabBar class]]) {
        UITabBar *tabBar = (UITabBar *)view;
        WriteLog(@"    barTintColor: %@", tabBar.barTintColor ?: @"nil");
        WriteLog(@"    translucent: %d", tabBar.translucent);
        WriteLog(@"    backgroundImage: %@", tabBar.backgroundImage ? @"exists" : @"nil");
        WriteLog(@"    shadowImage: %@", tabBar.shadowImage ? @"exists" : @"nil");
    }
}

// 递归打印子视图背景
static void logSubviewsBackground(UIView *view, NSInteger depth) {
    if (!view) return;
    NSString *indent = [@"  " stringByPaddingToLength:depth*2 withString:@" " startingAtIndex:0];
    WriteLog(@"%@%@ frame:%@ backgroundColor:%@ layer.bg:%@", indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame), view.backgroundColor ?: @"nil", view.layer.backgroundColor ? [UIColor colorWithCGColor:view.layer.backgroundColor] : @"nil");
    for (UIView *sub in view.subviews) {
        logSubviewsBackground(sub, depth+1);
    }
}

// =============================================================
// Hook SSTabBar — 只记录日志，不修改
// =============================================================
%hook SSTabBar

- (void)setAlpha:(CGFloat)alpha {
    WriteLog(@"SSTabBar setAlpha called with %.2f", alpha);
    %orig(alpha);
}

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    WriteLog(@"SSTabBar setItems called with %lu items", (unsigned long)items.count);
    if (isEnabled() && items.count > 2) {
        NSArray *filtered = @[items[0], items[4]];
        WriteLog(@"Filtering items to %@, %@", [(UITabBarItem *)items[0] title], [(UITabBarItem *)items[4] title]);
        %orig(filtered, animated);
        return;
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController — 记录生命周期和状态
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        WriteLog(@"  defaultTabIndex: %ld", (long)defaultTabIndex());
        WriteLog(@"  selectedIndex: %ld", (long)tab.selectedIndex);
        logViewBackground(tab.tabBar, @"tabBar in viewDidLoad");
    }
}

- (void)viewWillAppear:(BOOL)animated {
    WriteLog(@"SSTabBarController viewWillAppear (animated=%d)", animated);
    if (isEnabled() && defaultTabIndex() == 1) {
        UITabBarController *tab = (UITabBarController *)self;
        NSArray *vcs = tab.viewControllers;
        NSInteger myIndex = indexOfMyVC(vcs);
        if (myIndex != -1 && tab.selectedIndex != myIndex) {
            WriteLog(@"  Setting selectedIndex to %ld (my)", (long)myIndex);
            tab.selectedIndex = myIndex;
        } else {
            WriteLog(@"  selectedIndex already correct or myVC not found");
        }
    }
    %orig;
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        WriteLog(@"  after viewWillAppear: selectedIndex=%ld", (long)tab.selectedIndex);
        logViewBackground(tab.tabBar, @"tabBar in viewWillAppear (after)");
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewDidAppear");
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        WriteLog(@"  selectedIndex: %ld", (long)tab.selectedIndex);
        WriteLog(@"  selectedViewController: %@", NSStringFromClass([tab.selectedViewController class]));
        logViewBackground(tab.tabBar, @"tabBar in viewDidAppear");
        
        // 详细打印 tabBar 的所有子视图背景
        WriteLog(@"  tabBar subviews background detail:");
        logSubviewsBackground(tab.tabBar, 0);
        
        // 检查 tabBar 的 superview 背景
        UIView *superview = tab.tabBar.superview;
        WriteLog(@"  tabBar.superview: %@", NSStringFromClass([superview class]));
        logViewBackground(superview, @"  superview");
        
        // 检查主题状态
        id themeManager = NSClassFromString(@"AWEUIThemeManager");
        if (themeManager) {
            id shared = [themeManager performSelector:@selector(sharedManager)];
            if (shared) {
                BOOL isLight = [[shared valueForKey:@"isLightTheme"] boolValue];
                WriteLog(@"  AWEUIThemeManager isLightTheme: %d", isLight);
            }
        }
    }
}
%end

// =============================================================
// 双指双击菜单（保持原样）
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

static void showDefaultTabMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"默认打开页面"
                                                                   message:@"选择应用启动时默认进入的页面"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSInteger current = defaultTabIndex();
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 首页", current == 0 ? @"✓" : @""] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"HongGuoDefaultTab"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                         message:@"设置已保存，需要重启应用才能生效，是否立即重启？"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [restart addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        [restart addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:restart animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 我的", current == 1 ? @"✓" : @""] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"HongGuoDefaultTab"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                         message:@"设置已保存，需要重启应用才能生效，是否立即重启？"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [restart addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        [restart addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:restart animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }
    [topVC presentViewController:alert animated:YES completion:nil];
}

static void showSettingsMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;

    BOOL enabled = isEnabled();
    NSInteger defaultTab = defaultTabIndex();
    NSString *defaultText = defaultTab == 0 ? @"首页" : @"我的";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果精简Tab控制"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@\n默认打开：%@", enabled ? @"已开启" : @"已关闭", defaultText]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:enabled ? @"关闭功能" : @"开启功能" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"提示"
                                                                         message:@"切换后需重启 App 生效，确定？"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[NSUserDefaults standardUserDefaults] setBool:!enabled forKey:@"HongGuoFullScreenEnabled"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                             message:@"是否立即重启？"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [restart addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }]];
            [restart addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                showToast(@"请手动重启红果短剧", window);
            }]];
            UIViewController *top = window.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            [top presentViewController:restart animated:YES completion:nil];
        }]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:confirm animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"设置默认打开页面" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        showDefaultTabMenu(window);
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
// 构造函数
// =============================================================
%ctor {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"HongGuoFullScreenEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HongGuoFullScreenEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"HongGuoDefaultTab"]) {
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"HongGuoDefaultTab"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    WriteLog(@"HongGuoFullScreen 诊断版加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"开关状态: %@", isEnabled() ? @"开启" : @"关闭");
    WriteLog(@"默认打开: %@", defaultTabIndex() == 0 ? @"首页" : @"我的");
}
