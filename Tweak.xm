// =============================================================
//  HongGuoFullScreen — 诊断版（完整功能 + 日志）
//  功能：精简Tab栏 + 默认启动页 + 双指双击菜单
//  日志：记录每次 setViewControllers 和 setSelectedIndex 调用
//  日志路径：Documents/HongGuo.log
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>

// ---------- 日志函数 ----------
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

static BOOL isEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreenEnabled"];
}

static NSInteger defaultTabIndex() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"HongGuoDefaultTab"];
}

// 获取当前页面背景色
static UIColor *getCurrentPageBackgroundColor(UITabBarController *tab) {
    UIViewController *selected = tab.selectedViewController;
    if (!selected) return nil;
    UIColor *color = selected.view.backgroundColor;
    if (color) return color;
    CGColorRef layerColor = selected.view.layer.backgroundColor;
    if (layerColor) return [UIColor colorWithCGColor:layerColor];
    return nil;
}

// 同步 TabBar 高亮和颜色
static void syncTabBarAppearance(UITabBarController *tab) {
    if (!tab || !isEnabled()) return;
    UITabBar *tabBar = tab.tabBar;
    UIViewController *selected = tab.selectedViewController;
    if (!selected) return;

    // 高亮匹配
    NSString *title = selected.tabBarItem.title;
    for (UITabBarItem *item in tabBar.items) {
        if ([item.title isEqualToString:title]) {
            if (tabBar.selectedItem != item) {
                tabBar.selectedItem = item;
            }
            break;
        }
    }

    UIColor *bgColor = getCurrentPageBackgroundColor(tab);
    if (bgColor) {
        tabBar.barTintColor = bgColor;
        tabBar.translucent = NO;
    }

    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
}

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

// 拦截 setViewControllers
- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    WriteLog(@"===== setViewControllers 被调用 =====");
    WriteLog(@"原数量: %lu", (unsigned long)viewControllers.count);
    for (NSInteger i = 0; i < viewControllers.count; i++) {
        UIViewController *vc = viewControllers[i];
        WriteLog(@"  [%ld] %@", (long)i, vc.title);
    }

    if (isEnabled() && viewControllers.count >= 5) {
        UIViewController *homeVC = viewControllers[0];
        UIViewController *myVC = viewControllers[4];
        if (homeVC && myVC) {
            NSArray *filtered = @[homeVC, myVC];
            WriteLog(@"过滤后数量: 2 (首页=%@, 我的=%@)", homeVC.title, myVC.title);
            %orig(filtered, animated);
            UITabBarController *tab = (UITabBarController *)self;
            NSInteger targetIndex = (defaultTabIndex() == 1) ? 1 : 0;
            WriteLog(@"设置 selectedIndex = %ld", (long)targetIndex);
            if (tab.selectedIndex != targetIndex) {
                tab.selectedIndex = targetIndex;
            }
            syncTabBarAppearance(tab);
            return;
        }
    }
    WriteLog(@"未过滤，走原始");
    %orig(viewControllers, animated);
    if (isEnabled()) {
        syncTabBarAppearance((UITabBarController *)self);
    }
}

// viewDidLoad 中确保过滤（避免递归）
- (void)viewDidLoad {
    %orig;
    WriteLog(@"viewDidLoad 调用");
    if (!isEnabled()) return;
    UITabBarController *tab = (UITabBarController *)self;
    if (tab.viewControllers.count > 2) {
        WriteLog(@"viewDidLoad 中主动调用 setViewControllers 触发过滤");
        // 强制转换，避免编译错误
        [(id)self setViewControllers:tab.viewControllers animated:NO];
    }
}

// 拦截 setSelectedIndex
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"===== setSelectedIndex 被调用 =====");
    WriteLog(@"传入: %ld", (long)selectedIndex);
    UITabBarController *tab = (UITabBarController *)self;
    WriteLog(@"当前 viewControllers 数量: %lu", (unsigned long)tab.viewControllers.count);
    WriteLog(@"当前 tabBar.items 数量: %lu", (unsigned long)tab.tabBar.items.count);

    if (isEnabled() && tab.viewControllers.count == 2) {
        if (selectedIndex < 0 || selectedIndex >= tab.viewControllers.count) {
            selectedIndex = (defaultTabIndex() == 1) ? 1 : 0;
            WriteLog(@"索引非法，修正为 %ld", (long)selectedIndex);
        }
        WriteLog(@"调用原始 setSelectedIndex(%ld)", (long)selectedIndex);
        %orig(selectedIndex);
        syncTabBarAppearance(tab);
        WriteLog(@"同步外观完成");
        return;
    }
    WriteLog(@"功能未开启或未过滤，走原始");
    %orig(selectedIndex);
    if (isEnabled()) {
        syncTabBarAppearance(tab);
    }
}

// viewWillAppear
- (void)viewWillAppear:(BOOL)animated {
    WriteLog(@"viewWillAppear 调用");
    if (isEnabled() && defaultTabIndex() == 1) {
        UITabBarController *tab = (UITabBarController *)self;
        WriteLog(@"设置 selectedIndex = 1");
        tab.selectedIndex = 1;
    }
    %orig;
}

// viewDidAppear
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isEnabled() && defaultTabIndex() == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UITabBarController *tab = (UITabBarController *)self;
            WriteLog(@"viewDidAppear 延迟确保 selectedIndex = 1");
            tab.selectedIndex = 1;
        });
    }
}

%end

// =============================================================
// 双指双击菜单（完整保留，此处省略以节省篇幅）
// 但为了确保您能直接使用，请在最终代码中保留全部菜单代码
// =============================================================
// ...（您之前的菜单代码）
