// =============================================================
//  HongGuoFullScreen — 最终版（Hook UITabBar setItems: 强制过滤）
//  功能：精简Tab栏（首页、我的）+ 默认启动页 + 双指双击菜单
//  原理：拦截所有 setItems: 调用（包括系统内部），强制只保留首页和我的
//  日志：记录每次 setItems 和切换
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

// 强制过滤 tabBar.items 为首页和我的
static void forceFilterTabBarItems(UITabBar *tabBar, NSArray *viewControllers) {
    if (!tabBar || !viewControllers || viewControllers.count < 5) return;
    if (!isEnabled()) return;

    UITabBarItem *homeItem = ((UIViewController *)viewControllers[0]).tabBarItem;
    UITabBarItem *myItem = ((UIViewController *)viewControllers[4]).tabBarItem;
    if (homeItem && myItem) {
        // 检查当前 items 是否已经是首页和我的
        if (tabBar.items.count == 2 &&
            [tabBar.items[0].title isEqualToString:homeItem.title] &&
            [tabBar.items[1].title isEqualToString:myItem.title]) {
            // 已经是正确的，无需操作
            return;
        }
        WriteLog(@"强制过滤 items: 首页=%@, 我的=%@", homeItem.title, myItem.title);
        // 直接设置，不使用动画
        [tabBar setItems:@[homeItem, myItem] animated:NO];
    }
}

// =============================================================
// Hook UITabBar — 拦截所有 setItems: 调用
// =============================================================
%hook UITabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    // 先保存原始的 viewControllers（通过响应链获取 TabBarController）
    UITabBarController *tabController = nil;
    UIResponder *responder = (UIResponder *)self;
    while (responder && ![responder isKindOfClass:[UITabBarController class]]) {
        responder = [responder nextResponder];
    }
    if ([responder isKindOfClass:[UITabBarController class]]) {
        tabController = (UITabBarController *)responder;
    }

    // 如果功能开启且有 viewControllers，进行过滤
    if (isEnabled() && tabController && tabController.viewControllers.count >= 5) {
        NSArray *vcs = tabController.viewControllers;
        UITabBarItem *homeItem = ((UIViewController *)vcs[0]).tabBarItem;
        UITabBarItem *myItem = ((UIViewController *)vcs[4]).tabBarItem;
        if (homeItem && myItem) {
            // 拦截并替换为过滤后的 items
            NSArray *filtered = @[homeItem, myItem];
            WriteLog(@"UITabBar setItems 拦截: 原 %lu → 过滤后 %lu", (unsigned long)items.count, (unsigned long)filtered.count);
            %orig(filtered, animated);
            return;
        }
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController — 确保选中状态正确
// =============================================================
%hook SSTabBarController

// 在 viewDidLoad 中强制过滤一次
- (void)viewDidLoad {
    %orig;
    if (!isEnabled()) return;
    UITabBarController *tab = (UITabBarController *)self;
    if (tab.viewControllers.count >= 5) {
        forceFilterTabBarItems(tab.tabBar, tab.viewControllers);
        // 设置默认选中
        NSInteger targetIndex = (defaultTabIndex() == 1) ? 1 : 0;
        if (tab.selectedIndex != targetIndex) {
            tab.selectedIndex = targetIndex;
        }
    }
}

// 拦截 setViewControllers，在设置后过滤
- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    WriteLog(@"setViewControllers 被调用，原数量: %lu", (unsigned long)viewControllers.count);
    %orig(viewControllers, animated);
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        if (tab.viewControllers.count >= 5) {
            forceFilterTabBarItems(tab.tabBar, tab.viewControllers);
            NSInteger targetIndex = (defaultTabIndex() == 1) ? 1 : 0;
            if (tab.selectedIndex != targetIndex) {
                tab.selectedIndex = targetIndex;
            }
        }
    }
}

// 拦截 setSelectedIndex，直接切换视图并修正高亮
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"===== setSelectedIndex 被调用: %ld =====", (long)selectedIndex);
    UITabBarController *tab = (UITabBarController *)self;
    UITabBar *tabBar = tab.tabBar;

    if (!isEnabled() || tab.viewControllers.count < 5) {
        %orig(selectedIndex);
        return;
    }

    // 确保 items 已过滤
    forceFilterTabBarItems(tabBar, tab.viewControllers);

    // 映射索引：如果 selectedIndex >= 2，则映射为 0 或 1
    NSInteger filteredIndex = -1;
    if (selectedIndex < 2) {
        filteredIndex = selectedIndex;
    } else {
        if (selectedIndex == 0) filteredIndex = 0;
        else if (selectedIndex == 4) filteredIndex = 1;
        else filteredIndex = (defaultTabIndex() == 1) ? 1 : 0;
    }
    if (filteredIndex < 0 || filteredIndex > 1) filteredIndex = 0;
    WriteLog(@"映射后过滤索引: %ld", (long)filteredIndex);

    // 获取真实索引
    NSInteger realIndex = (filteredIndex == 0) ? 0 : 4;
    UIViewController *targetVC = tab.viewControllers[realIndex];
    if (tab.selectedViewController != targetVC) {
        tab.selectedViewController = targetVC;
    }

    // 修正高亮
    if (filteredIndex < tabBar.items.count) {
        UITabBarItem *item = tabBar.items[filteredIndex];
        if (tabBar.selectedItem != item) {
            tabBar.selectedItem = item;
        }
    }

    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
    WriteLog(@"切换完成，当前高亮: %@", tabBar.selectedItem.title);
}

// viewWillAppear 中确保默认页
- (void)viewWillAppear:(BOOL)animated {
    WriteLog(@"viewWillAppear 调用");
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        if (tab.viewControllers.count >= 5) {
            forceFilterTabBarItems(tab.tabBar, tab.viewControllers);
            NSInteger targetIndex = (defaultTabIndex() == 1) ? 1 : 0;
            if (tab.selectedIndex != targetIndex) {
                tab.selectedIndex = targetIndex;
            }
        }
    }
    %orig;
}

// viewDidAppear 中再次确保
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        if (tab.viewControllers.count >= 5) {
            forceFilterTabBarItems(tab.tabBar, tab.viewControllers);
            NSInteger targetIndex = (defaultTabIndex() == 1) ? 1 : 0;
            if (tab.selectedIndex != targetIndex) {
                tab.selectedIndex = targetIndex;
            }
        }
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
