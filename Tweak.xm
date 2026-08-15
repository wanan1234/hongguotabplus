// =============================================================
//  HongGuoFullScreen — 诊断版（只记录，不修改）
//  使用强制类型转换和KVC，确保编译通过
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
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"HongGuoDiagnostic.log"];

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

// ---------- 记录 tabBar 状态 ----------
static void logTabBarState(UITabBar *tabBar, NSString *tag) {
    if (!tabBar) {
        WriteLog(@"%@: tabBar is nil", tag);
        return;
    }
    WriteLog(@"===== %@ =====", tag);
    WriteLog(@"  class: %@", NSStringFromClass([tabBar class]));
    WriteLog(@"  frame: %@", NSStringFromCGRect(tabBar.frame));
    WriteLog(@"  alpha: %.3f", tabBar.alpha);
    WriteLog(@"  hidden: %d", tabBar.hidden);
    WriteLog(@"  barTintColor: %@", tabBar.barTintColor ?: @"nil");
    WriteLog(@"  translucent: %d", tabBar.translucent);
    WriteLog(@"  backgroundImage: %@", tabBar.backgroundImage ? @"exists" : @"nil");
    WriteLog(@"  shadowImage: %@", tabBar.shadowImage ? @"exists" : @"nil");
    WriteLog(@"  backgroundColor: %@", tabBar.backgroundColor ?: @"nil");
    
    WriteLog(@"  layer.backgroundColor: %@", tabBar.layer.backgroundColor ? [UIColor colorWithCGColor:tabBar.layer.backgroundColor] : @"nil");
    WriteLog(@"  layer.opacity: %.3f", tabBar.layer.opacity);
    WriteLog(@"  layer.hidden: %d", tabBar.layer.hidden);
    
    // 使用 KVC 获取 _backgroundView
    id backgroundView = [tabBar valueForKey:@"_backgroundView"];
    if (backgroundView) {
        WriteLog(@"  _backgroundView: %@", NSStringFromClass([backgroundView class]));
        WriteLog(@"    frame: %@", NSStringFromCGRect([backgroundView frame]));
        WriteLog(@"    alpha: %.3f", [backgroundView alpha]);
        WriteLog(@"    hidden: %d", [backgroundView isHidden]);
        // 使用 KVC 获取 backgroundColor，避免类型问题
        UIColor *bgColor = [backgroundView valueForKey:@"backgroundColor"];
        WriteLog(@"    backgroundColor: %@", bgColor ?: @"nil");
        WriteLog(@"    layer.backgroundColor: %@", [backgroundView layer].backgroundColor ? [UIColor colorWithCGColor:[backgroundView layer].backgroundColor] : @"nil");
        WriteLog(@"    layer.opacity: %.3f", [backgroundView layer].opacity);
        if ([backgroundView isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *effectView = (UIVisualEffectView *)backgroundView;
            WriteLog(@"    effect: %@", effectView.effect ? @"exists" : @"nil");
        }
    }
    
    WriteLog(@"  subviews count: %lu", (unsigned long)tabBar.subviews.count);
    for (UIView *sub in tabBar.subviews) {
        WriteLog(@"    sub: %@ frame=%@ alpha=%.3f hidden=%d bgColor=%@", 
                 NSStringFromClass([sub class]), 
                 NSStringFromCGRect(sub.frame), 
                 sub.alpha, 
                 sub.hidden,
                 sub.backgroundColor ?: @"nil");
        if ([sub isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *effectView = (UIVisualEffectView *)sub;
            WriteLog(@"      effect: %@", effectView.effect ? @"exists" : @"nil");
        }
    }
    WriteLog(@"===== end =====\n");
}

static void logControllerState(UITabBarController *tab, NSString *tag) {
    if (!tab) return;
    NSString *selectedTitle = tab.tabBar.selectedItem.title ?: @"nil";
    WriteLog(@"%@: selectedIndex=%ld, selectedItem=%@", 
             tag, 
             (long)tab.selectedIndex,
             selectedTitle);
}

// =============================================================
// Hook UITabBar（覆盖所有子类，包括 CYLTabBar 和 SSTabBar）
// =============================================================
%hook UITabBar

- (void)layoutSubviews {
    %orig;
    // 检测 alpha 变化
    static CGFloat lastAlpha = -1;
    if (fabs(self.alpha - lastAlpha) > 0.001) {
        lastAlpha = self.alpha;
        WriteLog(@"[UITabBar layoutSubviews] alpha changed to %.3f (class=%@)", self.alpha, NSStringFromClass([self class]));
        logTabBarState(self, @"layoutSubviews");
    }
}

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    WriteLog(@"[UITabBar setItems] count: %lu -> %lu (class=%@)", (unsigned long)self.items.count, (unsigned long)items.count, NSStringFromClass([self class]));
    %orig(items, animated);
    logTabBarState(self, @"after setItems");
}

- (void)setHidden:(BOOL)hidden {
    WriteLog(@"[UITabBar setHidden] %d -> %d (class=%@)", self.hidden, hidden, NSStringFromClass([self class]));
    %orig(hidden);
    logTabBarState(self, @"after setHidden");
}

- (void)setBarTintColor:(UIColor *)barTintColor {
    WriteLog(@"[UITabBar setBarTintColor] %@ -> %@ (class=%@)", self.barTintColor, barTintColor, NSStringFromClass([self class]));
    %orig(barTintColor);
    logTabBarState(self, @"after setBarTintColor");
}

- (void)setAlpha:(CGFloat)alpha {
    WriteLog(@"[UITabBar setAlpha] %.3f -> %.3f (class=%@)", self.alpha, alpha, NSStringFromClass([self class]));
    %orig(alpha);
    logTabBarState(self, @"after setAlpha");
}

%end

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"[SSTabBarController viewDidLoad]");
    UITabBarController *tab = (UITabBarController *)self;
    logControllerState(tab, @"viewDidLoad");
    logTabBarState(tab.tabBar, @"viewDidLoad tabBar");
}

- (void)viewWillAppear:(BOOL)animated {
    WriteLog(@"[SSTabBarController viewWillAppear] animated=%d", animated);
    %orig;
    UITabBarController *tab = (UITabBarController *)self;
    logControllerState(tab, @"viewWillAppear (after)");
    logTabBarState(tab.tabBar, @"viewWillAppear tabBar (after)");
}

- (void)viewDidAppear:(BOOL)animated {
    WriteLog(@"[SSTabBarController viewDidAppear] animated=%d", animated);
    %orig;
    UITabBarController *tab = (UITabBarController *)self;
    logControllerState(tab, @"viewDidAppear (after)");
    logTabBarState(tab.tabBar, @"viewDidAppear tabBar (after)");
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    UITabBarController *tab = (UITabBarController *)self;
    WriteLog(@"[SSTabBarController setSelectedIndex] %ld -> %ld", (long)tab.selectedIndex, (long)selectedIndex);
    %orig(selectedIndex);
    logControllerState(tab, @"after setSelectedIndex");
    logTabBarState(tab.tabBar, @"after setSelectedIndex tabBar");
}

%end

// =============================================================
// Hook AWEUIThemeManager（用 KVC 获取属性）
// =============================================================
%hook AWEUIThemeManager

- (void)setIsLightTheme:(BOOL)isLightTheme {
    // 获取旧值
    NSNumber *oldValue = [self valueForKey:@"isLightTheme"];
    WriteLog(@"[AWEUIThemeManager setIsLightTheme] %d -> %d", oldValue ? [oldValue boolValue] : -1, isLightTheme);
    %orig(isLightTheme);
    // 延迟记录 tabBar 状态
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
        UIViewController *root = window.rootViewController;
        if ([root isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
            UITabBarController *tab = (UITabBarController *)root;
            logTabBarState(tab.tabBar, @"after theme change");
        }
    });
}

%end

// =============================================================
// 双指双击菜单 + 查看日志
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

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果诊断"
                                                                   message:@"点击查看日志"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths firstObject];
        NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"HongGuoDiagnostic.log"];
        NSString *logContent = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        if (!logContent) logContent = @"日志文件不存在或为空";
        UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"诊断日志" message:logContent preferredStyle:UIAlertControllerStyleAlert];
        [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:logAlert animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
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
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 诊断版加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
}
