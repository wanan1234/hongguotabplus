// =============================================================
//  HongGuoFullScreen — 诊断版（保留所有功能+日志）
//  功能：精简Tab栏（首页、我的）+ 默认启动页 + 双指双击菜单
//  诊断：记录每次 selectedIndex 变化、视图切换、TabBar 状态
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
    NSLog(@"[HongGuo] %@", msg); // 也输出到控制台
}

static BOOL isEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreenEnabled"];
}

static NSInteger defaultTabIndex() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"HongGuoDefaultTab"];
}

// 获取“我的”在原始 viewControllers 中的真实索引（固定为4）
static NSInteger myRealIndex() {
    return 4;
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
// Hook SSTabBar — 只过滤 items
// =============================================================
%hook SSTabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    WriteLog(@"SSTabBar setItems 被调用，原始 items 数量: %lu", (unsigned long)items.count);
    if (isEnabled() && items.count > 2) {
        NSArray *filtered = @[items[0], items[4]];
        WriteLog(@"过滤后 items 数量: %lu (首页: %@, 我的: %@)", (unsigned long)filtered.count, items[0].title, items[4].title);
        %orig(filtered, animated);
        // 如果默认是我的，强制切换
        if (defaultTabIndex() == 1) {
            UIResponder *responder = (UIResponder *)self;
            while (responder && ![responder isKindOfClass:[UITabBarController class]]) {
                responder = [responder nextResponder];
            }
            if ([responder isKindOfClass:[UITabBarController class]]) {
                UITabBarController *tab = (UITabBarController *)responder;
                WriteLog(@"setItems 后强制设置 selectedIndex = 1");
                tab.selectedIndex = 1;
            }
        }
        return;
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController — 完全接管切换 + 日志
// =============================================================
%hook SSTabBarController

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    UITabBarController *tab = (UITabBarController *)self;
    UITabBar *tabBar = tab.tabBar;
    WriteLog(@"===== setSelectedIndex 被调用 =====");
    WriteLog(@"传入 selectedIndex = %ld", (long)selectedIndex);
    WriteLog(@"当前 viewControllers 数量: %lu", (unsigned long)tab.viewControllers.count);
    WriteLog(@"当前 tabBar.items 数量: %lu", (unsigned long)tabBar.items.count);
    WriteLog(@"当前 selectedViewController: %@", tab.selectedViewController);
    WriteLog(@"当前 selectedIndex (系统): %ld", (long)tab.selectedIndex);

    if (!isEnabled() || tabBar.items.count != 2) {
        WriteLog(@"功能未开启或未过滤，走原始逻辑");
        %orig(selectedIndex);
        if (isEnabled()) syncTabBarAppearance(tab);
        return;
    }

    // ---- 过滤模式：手动处理 ----
    NSInteger realIndex = -1;
    NSInteger filteredIndex = -1;

    // 判断传入索引含义
    if (selectedIndex < 2) {
        // 过滤索引
        filteredIndex = selectedIndex;
        if (selectedIndex == 0) {
            realIndex = 0;
            WriteLog(@"识别为过滤索引 0 → 真实索引 0 (首页)");
        } else if (selectedIndex == 1) {
            realIndex = myRealIndex();
            WriteLog(@"识别为过滤索引 1 → 真实索引 %ld (我的)", (long)realIndex);
        }
    } else {
        // 真实索引
        if (selectedIndex == 0) {
            filteredIndex = 0;
            realIndex = 0;
            WriteLog(@"识别为真实索引 0 → 过滤索引 0 (首页)");
        } else if (selectedIndex == myRealIndex()) {
            filteredIndex = 1;
            realIndex = selectedIndex;
            WriteLog(@"识别为真实索引 %ld → 过滤索引 1 (我的)", (long)realIndex);
        } else {
            // 其他真实索引（剧场等）→ 重定向到首页
            filteredIndex = 0;
            realIndex = 0;
            WriteLog(@"识别为其他真实索引 %ld → 重定向到首页 (过滤索引 0)", (long)selectedIndex);
        }
    }

    if (realIndex < 0 || realIndex >= tab.viewControllers.count) {
        WriteLog(@"⚠️ 真实索引无效，回退到 0");
        realIndex = 0;
        filteredIndex = 0;
    }

    UIViewController *targetVC = tab.viewControllers[realIndex];
    WriteLog(@"最终决定切换到真实索引 %ld, 控制器: %@", (long)realIndex, targetVC);

    // 1. 切换视图
    if (tab.selectedViewController != targetVC) {
        tab.selectedViewController = targetVC;
        WriteLog(@"视图已切换");
    } else {
        WriteLog(@"视图未变化");
    }

    // 2. 修正高亮
    if (filteredIndex >= 0 && filteredIndex < tabBar.items.count) {
        UITabBarItem *item = tabBar.items[filteredIndex];
        WriteLog(@"设置高亮 item: %@ (过滤索引 %ld)", item.title, (long)filteredIndex);
        if (tabBar.selectedItem != item) {
            tabBar.selectedItem = item;
        }
    }

    // 3. 同步颜色
    syncTabBarAppearance(tab);
    WriteLog(@"颜色同步完成，barTintColor: %@", tabBar.barTintColor);
    WriteLog(@"===== setSelectedIndex 处理结束 =====");
}

// viewWillAppear 中设置默认启动页
- (void)viewWillAppear:(BOOL)animated {
    WriteLog(@"viewWillAppear 调用");
    if (isEnabled() && defaultTabIndex() == 1) {
        WriteLog(@"默认启动是我的，设置 selectedIndex = 1");
        ((UITabBarController *)self).selectedIndex = 1;
    }
    %orig;
}

// viewDidAppear 中再次确保
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isEnabled() && defaultTabIndex() == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WriteLog(@"viewDidAppear 延迟确保 selectedIndex = 1");
            ((UITabBarController *)self).selectedIndex = 1;
        });
    }
}

%end

// =============================================================
// 双指双击菜单（完整保留）
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
                                                                         message:@"设置已保存，是否立即重启生效？"
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

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 我的", current == 1 ? @"✓" : @""] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"HongGuoDefaultTab"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                         message:@"设置已保存，是否立即重启生效？"
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
    WriteLog(@"====== HongGuoFullScreen 加载完成 ======");
    WriteLog(@"功能状态: %@", isEnabled() ? @"开启" : @"关闭");
    WriteLog(@"默认启动页: %@", defaultTabIndex() == 0 ? @"首页" : @"我的");
}
