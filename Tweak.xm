// =============================================================
//  HongGuoFullScreen — 最终版（自动重新过滤 + 完整菜单）
//  功能：精简Tab栏 + 默认启动页 + 双指双击菜单
//  原理：拦截 setItems 过滤，并在切换时检测 items 数量，自动修复
//  日志：记录关键操作到 Documents/HongGuo.log
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

// 手动切换视图并同步高亮和颜色
static void switchToTab(UITabBarController *tab, NSInteger filteredIndex) {
    if (!tab || !isEnabled()) return;
    NSArray *vcs = tab.viewControllers;
    if (vcs.count < 5) return;
    UITabBar *tabBar = tab.tabBar;
    if (tabBar.items.count != 2) {
        WriteLog(@"⚠️ tabBar.items 数量不是2，当前: %lu，尝试重新过滤", (unsigned long)tabBar.items.count);
        // 主动过滤 items
        UITabBarItem *homeItem = vcs[0].tabBarItem;
        UITabBarItem *myItem = vcs[4].tabBarItem;
        if (homeItem && myItem) {
            [tabBar setItems:@[homeItem, myItem] animated:NO];
            WriteLog(@"已重新过滤 items");
        }
        // 延迟再次调用自己，等待 items 更新
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            switchToTab(tab, filteredIndex);
        });
        return;
    }

    NSInteger realIndex = -1;
    UITabBarItem *targetItem = nil;
    if (filteredIndex == 0) {
        realIndex = 0;
        if (tabBar.items.count > 0) targetItem = tabBar.items[0];
    } else if (filteredIndex == 1) {
        realIndex = 4;
        if (tabBar.items.count > 1) targetItem = tabBar.items[1];
    } else {
        WriteLog(@"⚠️ 无效的过滤索引: %ld", (long)filteredIndex);
        return;
    }

    if (realIndex < 0 || realIndex >= vcs.count) {
        WriteLog(@"⚠️ 真实索引无效: %ld", (long)realIndex);
        return;
    }

    UIViewController *targetVC = vcs[realIndex];
    WriteLog(@"手动切换: 过滤索引 %ld → 真实索引 %ld, 控制器: %@", (long)filteredIndex, (long)realIndex, targetVC);

    if (tab.selectedViewController != targetVC) {
        tab.selectedViewController = targetVC;
        WriteLog(@"视图已切换");
    }

    if (targetItem && tabBar.selectedItem != targetItem) {
        tabBar.selectedItem = targetItem;
        WriteLog(@"高亮已修正: %@", targetItem.title);
    }

    UIColor *bgColor = getCurrentPageBackgroundColor(tab);
    if (bgColor) {
        tabBar.barTintColor = bgColor;
        tabBar.translucent = NO;
        WriteLog(@"颜色已同步: %@", bgColor);
    }

    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
}

// =============================================================
// Hook SSTabBar — 过滤 items
// =============================================================
%hook SSTabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    if (isEnabled() && items.count > 2) {
        UITabBarItem *homeItem = items[0];
        UITabBarItem *myItem = items[4];
        NSArray *filtered = @[homeItem, myItem];
        WriteLog(@"SSTabBar 过滤: 原 %lu → 过滤后 %lu (首页=%@, 我的=%@)", (unsigned long)items.count, (unsigned long)filtered.count, homeItem.title, myItem.title);
        %orig(filtered, animated);
        // 如果默认是我的，立即切换
        if (defaultTabIndex() == 1) {
            UIResponder *responder = (UIResponder *)self;
            while (responder && ![responder isKindOfClass:[UITabBarController class]]) {
                responder = [responder nextResponder];
            }
            if ([responder isKindOfClass:[UITabBarController class]]) {
                UITabBarController *tab = (UITabBarController *)responder;
                WriteLog(@"setItems 后切换到我的");
                // 延迟执行，确保 items 已更新
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    switchToTab(tab, 1);
                });
            }
        }
        return;
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController — 拦截切换
// =============================================================
%hook SSTabBarController

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    UITabBarController *tab = (UITabBarController *)self;
    WriteLog(@"===== setSelectedIndex 被调用，传入: %ld =====", (long)selectedIndex);
    WriteLog(@"tabBar.items 数量: %lu", (unsigned long)tab.tabBar.items.count);

    if (!isEnabled()) {
        WriteLog(@"功能关闭，走原始逻辑");
        %orig(selectedIndex);
        return;
    }

    // 如果 items 数量不是 2，主动过滤并延迟重试
    if (tab.tabBar.items.count != 2) {
        WriteLog(@"items 数量不是2，尝试重新过滤");
        NSArray *vcs = tab.viewControllers;
        if (vcs.count >= 5) {
            UITabBarItem *homeItem = vcs[0].tabBarItem;
            UITabBarItem *myItem = vcs[4].tabBarItem;
            if (homeItem && myItem) {
                [tab.tabBar setItems:@[homeItem, myItem] animated:NO];
                WriteLog(@"已重新设置 items");
                // 延迟再次调用自己
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    WriteLog(@"延迟重试 setSelectedIndex:%ld", (long)selectedIndex);
                    [(id)self setSelectedIndex:selectedIndex];
                });
                return;
            }
        }
    }

    // 此时 items 应该是 2，进行手动切换
    NSInteger filteredIndex = -1;
    if (selectedIndex < 2) {
        filteredIndex = selectedIndex;
    } else {
        if (selectedIndex == 0) filteredIndex = 0;
        else if (selectedIndex == 4) filteredIndex = 1;
        else filteredIndex = 0;
        WriteLog(@"真实索引 %ld → 映射为过滤索引 %ld", (long)selectedIndex, (long)filteredIndex);
    }

    if (filteredIndex < 0 || filteredIndex > 1) {
        filteredIndex = 0;
        WriteLog(@"过滤索引无效，回退到0");
    }

    switchToTab(tab, filteredIndex);
    WriteLog(@"===== setSelectedIndex 处理结束 =====");
}

- (void)viewWillAppear:(BOOL)animated {
    WriteLog(@"viewWillAppear 调用");
    if (isEnabled() && defaultTabIndex() == 1) {
        WriteLog(@"默认启动是我的，调用 setSelectedIndex:1");
        [(id)self setSelectedIndex:1];
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isEnabled() && defaultTabIndex() == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WriteLog(@"viewDidAppear 延迟确保切换到我的");
            [(id)self setSelectedIndex:1];
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
