// =============================================================
//  HongGuoFullScreen — 诊断版（提取日志，不猜测）
//  功能：精简Tab栏 + 默认启动页 + 双指双击菜单 + 详细日志
//  日志路径：沙盒 Documents/HongGuo.log
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>

// ---------- 日志工具 ----------
static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = [paths firstObject];
    NSString *logPath = [docPath stringByAppendingPathComponent:@"HongGuo.log"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:docPath]) {
        [fm createDirectoryAtPath:docPath withIntermediateDirectories:YES attributes:nil error:nil];
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

// 获取“我的”真实索引（动态查找）
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

    NSString *title = selected.tabBarItem.title;
    for (UITabBarItem *item in tabBar.items) {
        if ([item.title isEqualToString:title]) {
            if (tabBar.selectedItem != item) {
                tabBar.selectedItem = item;
                WriteLog(@"高亮修正: 选中 item 标题=%@", item.title);
            }
            break;
        }
    }

    UIColor *bgColor = getCurrentPageBackgroundColor(tab);
    if (bgColor) {
        tabBar.barTintColor = bgColor;
        tabBar.translucent = NO;
        WriteLog(@"颜色设置: barTintColor=%@", bgColor);
    }

    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
}

// =============================================================
// Hook SSTabBar — 过滤 items 并记录日志
// =============================================================
%hook SSTabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    NSMutableArray *titles = [NSMutableArray array];
    for (UITabBarItem *item in items) {
        [titles addObject:item.title ?: @"(nil)"];
    }
    WriteLog(@"SSTabBar setItems 原始: %@", [titles componentsJoinedByString:@", "]);

    if (isEnabled() && items.count > 2) {
        // 动态查找“我的”和“首页”
        NSInteger homeIdx = 0;
        NSInteger myIdx = -1;
        for (NSInteger i = 0; i < items.count; i++) {
            if ([items[i].title isEqualToString:@"首页"]) homeIdx = i;
            if ([items[i].title isEqualToString:@"我的"]) myIdx = i;
        }
        if (myIdx == -1) {
            WriteLog(@"错误: 未找到‘我的’item，保留全部");
            %orig(items, animated);
            return;
        }
        NSArray *filtered = @[items[homeIdx], items[myIdx]];
        WriteLog(@"过滤后 items: %@, %@", [filtered[0] title], [filtered[1] title]);
        %orig(filtered, animated);

        // 如果默认是我的，切换
        if (defaultTabIndex() == 1) {
            UIResponder *responder = (UIResponder *)self;
            while (responder && ![responder isKindOfClass:[UITabBarController class]]) {
                responder = [responder nextResponder];
            }
            if ([responder isKindOfClass:[UITabBarController class]]) {
                UITabBarController *tab = (UITabBarController *)responder;
                WriteLog(@"默认启动我的，设置 selectedIndex=1");
                tab.selectedIndex = 1;
            }
        }
        return;
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController — 完全接管切换，记录日志
// =============================================================
%hook SSTabBarController

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    UITabBarController *tab = (UITabBarController *)self;
    UITabBar *tabBar = tab.tabBar;
    WriteLog(@"setSelectedIndex 传入: %ld, 当前 items 数: %lu", (long)selectedIndex, (unsigned long)tabBar.items.count);

    if (!isEnabled() || tabBar.items.count != 2) {
        WriteLog(@"未启用过滤或未过滤，走原始");
        %orig(selectedIndex);
        if (isEnabled()) syncTabBarAppearance(tab);
        return;
    }

    // ---- 过滤模式：手动处理 ----
    NSInteger realIndex = -1;
    NSInteger filteredIndex = -1;

    // 获取“我的”真实索引
    NSInteger myRealIdx = indexOfMyVC(tab.viewControllers);
    WriteLog(@"我的真实索引: %ld", (long)myRealIdx);

    // 判断传入的 selectedIndex 是过滤索引还是真实索引
    if (selectedIndex < tabBar.items.count) {
        // 过滤索引
        filteredIndex = selectedIndex;
        if (selectedIndex == 0) {
            realIndex = 0; // 首页
        } else if (selectedIndex == 1) {
            realIndex = myRealIdx;
        }
        WriteLog(@"传入的是过滤索引 %ld -> 真实索引 %ld", (long)filteredIndex, (long)realIndex);
    } else {
        // 真实索引
        if (selectedIndex == 0) {
            filteredIndex = 0;
            realIndex = 0;
        } else if (selectedIndex == myRealIdx) {
            filteredIndex = 1;
            realIndex = selectedIndex;
        } else {
            // 其他真实索引（如剧场）→ 重定向到首页
            filteredIndex = 0;
            realIndex = 0;
            WriteLog(@"传入其他真实索引 %ld，重定向到首页", (long)selectedIndex);
        }
    }

    if (realIndex < 0 || realIndex >= tab.viewControllers.count) {
        realIndex = 0;
        filteredIndex = 0;
        WriteLog(@"索引修正: 设为首页");
    }

    UIViewController *targetVC = tab.viewControllers[realIndex];
    WriteLog(@"切换视图: %@ (真实索引 %ld)", targetVC.tabBarItem.title, (long)realIndex);

    if (tab.selectedViewController != targetVC) {
        tab.selectedViewController = targetVC;
    }

    // 修正高亮
    if (filteredIndex >= 0 && filteredIndex < tabBar.items.count) {
        UITabBarItem *targetItem = tabBar.items[filteredIndex];
        if (tabBar.selectedItem != targetItem) {
            tabBar.selectedItem = targetItem;
            WriteLog(@"设置高亮 item: %@", targetItem.title);
        }
    }

    syncTabBarAppearance(tab);
    WriteLog(@"切换完成，当前 selectedViewController=%@, selectedItem=%@",
              tab.selectedViewController.tabBarItem.title,
              tabBar.selectedItem.title);
}

// viewWillAppear
- (void)viewWillAppear:(BOOL)animated {
    if (isEnabled() && defaultTabIndex() == 1) {
        WriteLog(@"viewWillAppear: 设置 selectedIndex=1");
        ((UITabBarController *)self).selectedIndex = 1;
    }
    %orig;
}

// viewDidAppear
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isEnabled() && defaultTabIndex() == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WriteLog(@"viewDidAppear 延迟: 设置 selectedIndex=1");
            ((UITabBarController *)self).selectedIndex = 1;
        });
    }
}

%end

// =============================================================
// 双指双击菜单（完整版）
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
    WriteLog(@"=== HongGuoFullScreen 初始化完成 ===");
}
