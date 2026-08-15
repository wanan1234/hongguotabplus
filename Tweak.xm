// =============================================================
//  HongGuoFullScreen — 最终修复版（颜色 + 隐藏遮挡）
//  功能：精简Tab栏 + 默认启动页 + 双指双击菜单
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

// 获取当前页面背景色（修复：优先取 view.backgroundColor）
static UIColor *getCurrentPageBackgroundColor(UITabBarController *tab) {
    UIViewController *selected = tab.selectedViewController;
    if (!selected) return nil;
    
    // 方法1：直接取 view.backgroundColor
    UIColor *color = selected.view.backgroundColor;
    if (color && ![color isEqual:[UIColor clearColor]]) {
        return color;
    }
    
    // 方法2：取 view 的 layer 背景色
    CGColorRef layerColor = selected.view.layer.backgroundColor;
    if (layerColor) {
        UIColor *layerColorUI = [UIColor colorWithCGColor:layerColor];
        if (layerColorUI && ![layerColorUI isEqual:[UIColor clearColor]]) {
            return layerColorUI;
        }
    }
    
    // 方法3：尝试取 scrollView 背景色
    if ([selected.view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scrollView = (UIScrollView *)selected.view;
        if (scrollView.backgroundColor) {
            return scrollView.backgroundColor;
        }
    }
    
    // 方法4：默认白色（用于我的页面）
    return [UIColor whiteColor];
}

// 强制修正 TabBar 颜色（专门修复黑色问题）
static void fixTabBarColor(UITabBarController *tab) {
    if (!tab || !isEnabled()) return;
    UITabBar *tabBar = tab.tabBar;
    UIViewController *selected = tab.selectedViewController;
    if (!selected) return;
    
    // 根据当前页面设置颜色
    UIColor *bgColor = getCurrentPageBackgroundColor(tab);
    WriteLog(@"fixTabBarColor: 当前控制器=%@, 背景色=%@", selected, bgColor);
    
    if (bgColor) {
        tabBar.barTintColor = bgColor;
        tabBar.translucent = NO;
        // 强制刷新
        [tabBar setNeedsLayout];
        [tabBar layoutIfNeeded];
        WriteLog(@"fixTabBarColor: 已设置 barTintColor=%@", bgColor);
    }
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

    // 修复颜色
    fixTabBarColor(tab);
}

// 隐藏“我的”页面顶部的白色遮挡区域
static void hideMyPageTopBanner(UIViewController *myVC) {
    if (!myVC) return;
    WriteLog(@"hideMyPageTopBanner: 尝试隐藏顶部遮挡");
    
    // 方法1：查找高度 318 的 FQReaderSaaSBaseImageView（横幅）
    for (UIView *sub in myVC.view.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"FQReaderSaaSBaseImageView"]) {
            if (sub.frame.size.height > 300) {
                sub.hidden = YES;
                WriteLog(@"已隐藏横幅: %@", NSStringFromCGRect(sub.frame));
            }
        }
    }
    
    // 方法2：查找滚动视图内的顶部占位视图（高度91）
    for (UIView *sub in myVC.view.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollView"]) {
            if ([sub isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)sub;
                for (UIView *contentView in scrollView.subviews) {
                    if ([NSStringFromClass([contentView class]) isEqualToString:@"SSMyUser637NestedContainerScrollContentView"]) {
                        if (contentView.subviews.count > 0) {
                            UIView *firstChild = contentView.subviews[0];
                            if (firstChild.frame.size.height >= 80 && firstChild.frame.size.height <= 100) {
                                firstChild.hidden = YES;
                                WriteLog(@"已隐藏滚动内容顶部占位视图");
                            }
                        }
                        break;
                    }
                }
            }
        }
    }
    
    // 方法3：强制滚动到顶部，消除空白
    for (UIView *sub in myVC.view.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollView"]) {
            if ([sub isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)sub;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [scrollView setContentOffset:CGPointMake(0, 0) animated:NO];
                    WriteLog(@"已归零滚动视图偏移");
                });
                break;
            }
        }
    }
}

// 强制过滤 tabBar.items
static void forceFilterTabBarItems(UITabBarController *tab) {
    if (!tab || !isEnabled()) return;
    UITabBar *tabBar = tab.tabBar;
    NSArray *vcs = tab.viewControllers;
    if (vcs.count < 5) return;

    UITabBarItem *homeItem = ((UIViewController *)vcs[0]).tabBarItem;
    UITabBarItem *myItem = ((UIViewController *)vcs[4]).tabBarItem;
    if (homeItem && myItem) {
        if (tabBar.items.count != 2 ||
            ![tabBar.items[0].title isEqualToString:homeItem.title] ||
            ![tabBar.items[1].title isEqualToString:myItem.title]) {
            WriteLog(@"强制过滤 items: 首页=%@, 我的=%@", homeItem.title, myItem.title);
            [tabBar setItems:@[homeItem, myItem] animated:NO];
            // 过滤后立即修复颜色
            fixTabBarColor(tab);
        }
    }
}

// 手动切换视图并同步高亮和颜色
static void switchToTab(UITabBarController *tab, NSInteger filteredIndex) {
    if (!tab || !isEnabled()) return;
    NSArray *vcs = tab.viewControllers;
    if (vcs.count < 5) return;
    UITabBar *tabBar = tab.tabBar;

    // 确保 items 已过滤
    forceFilterTabBarItems(tab);

    NSInteger realIndex = -1;
    if (filteredIndex == 0) realIndex = 0;
    else if (filteredIndex == 1) realIndex = 4;
    else {
        WriteLog(@"⚠️ 无效过滤索引: %ld", (long)filteredIndex);
        return;
    }

    if (realIndex < 0 || realIndex >= vcs.count) return;

    UIViewController *targetVC = vcs[realIndex];
    WriteLog(@"切换: 过滤索引 %ld → 真实索引 %ld, 控制器=%@", (long)filteredIndex, (long)realIndex, targetVC);

    // 切换视图
    if (tab.selectedViewController != targetVC) {
        tab.selectedViewController = targetVC;
    }

    // 修正高亮
    if (filteredIndex >= 0 && filteredIndex < tabBar.items.count) {
        UITabBarItem *item = tabBar.items[filteredIndex];
        if (tabBar.selectedItem != item) {
            tabBar.selectedItem = item;
        }
    }

    // 修复颜色
    fixTabBarColor(tab);
    
    // 如果切换到我的页面，隐藏顶部遮挡
    if (filteredIndex == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            hideMyPageTopBanner(targetVC);
        });
    }
}

// =============================================================
// Hook SSTabBar
// =============================================================
%hook SSTabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    if (isEnabled() && items.count > 2) {
        UITabBarItem *homeItem = items[0];
        UITabBarItem *myItem = items[4];
        NSArray *filtered = @[homeItem, myItem];
        WriteLog(@"SSTabBar 过滤: 原 %lu → 过滤后 %lu", (unsigned long)items.count, (unsigned long)filtered.count);
        %orig(filtered, animated);
        
        UIResponder *responder = (UIResponder *)self;
        while (responder && ![responder isKindOfClass:[UITabBarController class]]) {
            responder = [responder nextResponder];
        }
        if ([responder isKindOfClass:[UITabBarController class]]) {
            UITabBarController *tab = (UITabBarController *)responder;
            NSInteger targetIndex = (defaultTabIndex() == 1) ? 1 : 0;
            switchToTab(tab, targetIndex);
        }
        return;
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    WriteLog(@"setViewControllers 被调用，原数量: %lu", (unsigned long)viewControllers.count);
    %orig(viewControllers, animated);
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        forceFilterTabBarItems(tab);
        if (defaultTabIndex() == 1) {
            switchToTab(tab, 1);
        }
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"===== setSelectedIndex 被调用: %ld =====", (long)selectedIndex);
    UITabBarController *tab = (UITabBarController *)self;
    UITabBar *tabBar = tab.tabBar;

    if (!isEnabled()) {
        %orig(selectedIndex);
        return;
    }

    forceFilterTabBarItems(tab);

    NSInteger filteredIndex = -1;
    if (selectedIndex < tabBar.items.count) {
        filteredIndex = selectedIndex;
    } else {
        if (selectedIndex == 0) filteredIndex = 0;
        else if (selectedIndex == 4) filteredIndex = 1;
        else filteredIndex = (defaultTabIndex() == 1) ? 1 : 0;
    }
    if (filteredIndex < 0 || filteredIndex > 1) filteredIndex = 0;

    WriteLog(@"映射后过滤索引: %ld", (long)filteredIndex);
    switchToTab(tab, filteredIndex);
}

- (void)viewWillAppear:(BOOL)animated {
    WriteLog(@"viewWillAppear 调用");
    if (isEnabled() && defaultTabIndex() == 1) {
        UITabBarController *tab = (UITabBarController *)self;
        forceFilterTabBarItems(tab);
        switchToTab(tab, 1);
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isEnabled() && defaultTabIndex() == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UITabBarController *tab = (UITabBarController *)self;
            forceFilterTabBarItems(tab);
            switchToTab(tab, 1);
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
