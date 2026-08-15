// =============================================================
//  FanQieNoTabs — 番茄小说插件（修复默认启动页）
//  功能：隐藏「短剧」「我的」「福利」Tab，默认启动页设置
//  手势：双指双击菜单，切换需重启
// =============================================================
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ---------- 开关判断 ----------
static BOOL FQIsEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"FanQieNoTabsEnabled"];
}

static BOOL FQShouldApply() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.dragon.read"] && FQIsEnabled();
}

// 默认启动页：0=书城，1=书架
static NSInteger FQDefaultTab() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"FanQieDefaultTab"];
}

// 过滤 items
static NSArray<UITabBarItem *> *FQFilterItems(NSArray<UITabBarItem *> *items) {
    if (!FQIsEnabled()) return items;
    if (items.count == 0) return items;
    NSMutableArray *result = [NSMutableArray array];
    for (UITabBarItem *item in items) {
        NSString *title = item.title;
        if (title && ([title isEqualToString:@"短剧"] || [title isEqualToString:@"我的"] || [title isEqualToString:@"福利"])) {
            continue;
        }
        [result addObject:item];
    }
    return result;
}

// 过滤 ViewControllers
static NSArray<UIViewController *> *FQFilterViewControllers(NSArray<UIViewController *> *vcs) {
    if (!FQIsEnabled()) return vcs;
    if (vcs.count == 0) return vcs;
    NSMutableArray *result = [NSMutableArray array];
    for (UIViewController *vc in vcs) {
        NSString *title = vc.tabBarItem.title;
        if (title && ([title isEqualToString:@"短剧"] || [title isEqualToString:@"我的"] || [title isEqualToString:@"福利"])) {
            continue;
        }
        [result addObject:vc];
    }
    return result;
}

// 获取“书架”视图控制器的索引
static NSInteger FQIndexOfShelfVC(NSArray<UIViewController *> *vcs) {
    for (NSInteger i = 0; i < vcs.count; i++) {
        NSString *title = vcs[i].tabBarItem.title;
        if ([title isEqualToString:@"书架"]) {
            return i;
        }
    }
    return -1;
}

// =============================================================
// Hook 部分
// =============================================================
%hook UITabBar
- (void)setItems:(NSArray<UITabBarItem *> *)items animated:(BOOL)animated {
    if (FQShouldApply()) {
        items = FQFilterItems(items);
    }
    %orig(items, animated);
}
%end

%hook UITabBarController
- (void)viewDidLoad {
    %orig;
    if (FQShouldApply()) {
        // 首次过滤 viewControllers
        NSArray *filtered = FQFilterViewControllers(self.viewControllers);
        if (filtered.count < self.viewControllers.count) {
            [self setViewControllers:filtered animated:NO];
        }
        // 设置默认启动页（放在这里确保 viewControllers 已过滤）
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSInteger defaultTab = FQDefaultTab();
            if (defaultTab == 1) { // 书架
                NSInteger shelfIndex = FQIndexOfShelfVC(self.viewControllers);
                if (shelfIndex != -1) {
                    self.selectedIndex = shelfIndex;
                } else {
                    self.selectedIndex = 0;
                }
            } else {
                self.selectedIndex = 0; // 书城
            }
            [self.tabBar setNeedsLayout];
            [self.tabBar layoutIfNeeded];
        });
    }
}

// 在 viewDidAppear 中兜底，防止被重置
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!FQShouldApply()) return;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 延迟一帧确保完全加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSInteger defaultTab = FQDefaultTab();
            if (defaultTab == 1) {
                NSInteger shelfIndex = FQIndexOfShelfVC(self.viewControllers);
                if (shelfIndex != -1 && self.selectedIndex != shelfIndex) {
                    self.selectedIndex = shelfIndex;
                    [self.tabBar setNeedsLayout];
                    [self.tabBar layoutIfNeeded];
                }
            }
        });
    });
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    if (FQShouldApply()) {
        NSArray *filtered = FQFilterViewControllers(viewControllers);
        %orig(filtered, animated);
        NSArray *filteredItems = FQFilterItems(self.tabBar.items);
        [self.tabBar setValue:filteredItems forKey:@"items"];
        [self.tabBar setNeedsLayout];
        [self.tabBar layoutIfNeeded];
        return;
    }
    %orig(viewControllers, animated);
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers {
    if (FQShouldApply()) {
        NSArray *filtered = FQFilterViewControllers(viewControllers);
        %orig(filtered);
        NSArray *filteredItems = FQFilterItems(self.tabBar.items);
        [self.tabBar setValue:filteredItems forKey:@"items"];
        [self.tabBar setNeedsLayout];
        [self.tabBar layoutIfNeeded];
        return;
    }
    %orig(viewControllers);
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (FQShouldApply()) {
        if (selectedIndex >= self.viewControllers.count) {
            selectedIndex = 0;
        }
        if (selectedIndex < self.viewControllers.count) {
            UIViewController *targetVC = self.viewControllers[selectedIndex];
            NSString *title = targetVC.tabBarItem.title;
            if ([title isEqualToString:@"短剧"]) {
                NSInteger shelfIndex = FQIndexOfShelfVC(self.viewControllers);
                if (shelfIndex != -1) {
                    selectedIndex = shelfIndex;
                } else {
                    selectedIndex = 0;
                }
            }
        }
        %orig(selectedIndex);
        return;
    }
    %orig(selectedIndex);
}
%end

// =============================================================
// 手势控制：双指双击菜单（含重启确认）
// =============================================================

static void showToast(NSString *msg, UIWindow *window) {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

// 默认启动页设置子菜单
static void showDefaultTabMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"默认启动页"
                                                                   message:@"选择应用启动时默认进入的页面"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSInteger current = FQDefaultTab();
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 书城", current == 0 ? @"✓" : @""] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"FanQieDefaultTab"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        // 询问重启
        UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                         message:@"设置已保存，需要重启应用才能生效，是否立即重启？"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [restart addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        [restart addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:restart animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 书架", current == 1 ? @"✓" : @""] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"FanQieDefaultTab"];
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
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    BOOL enabled = FQIsEnabled();
    NSInteger defaultTab = FQDefaultTab();
    NSString *defaultText = defaultTab == 0 ? @"书城" : @"书架";
    NSString *status = enabled ? @"已开启" : @"已关闭";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"番茄小说界面控制"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@\n默认启动：%@", status, defaultText]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 开关切换（含重启确认）
    NSString *actionTitle = enabled ? @"关闭隐藏功能" : @"开启隐藏功能";
    [alert addAction:[UIAlertAction actionWithTitle:actionTitle
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                // 先确认切换
                                                UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                                                                       message:@"切换后需要重启 App 才能完全生效，确定要继续吗？"
                                                                                                                preferredStyle:UIAlertControllerStyleAlert];
                                                [confirmAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                                                    BOOL newState = !enabled;
                                                    [[NSUserDefaults standardUserDefaults] setBool:newState forKey:@"FanQieNoTabsEnabled"];
                                                    [[NSUserDefaults standardUserDefaults] synchronize];
                                                    // 询问重启
                                                    UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                                                                     message:[NSString stringWithFormat:@"已%@隐藏功能，需要重启应用才能生效，是否立即重启？", newState ? @"开启" : @"关闭"]
                                                                                                              preferredStyle:UIAlertControllerStyleAlert];
                                                    [restart addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                                                        exit(0);
                                                    }]];
                                                    [restart addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
                                                    [topVC presentViewController:restart animated:YES completion:nil];
                                                }]];
                                                [confirmAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                                                UIViewController *top = window.rootViewController;
                                                while (top.presentedViewController) {
                                                    top = top.presentedViewController;
                                                }
                                                [top presentViewController:confirmAlert animated:YES completion:nil];
                                            }]];
    
    // 设置默认启动页
    [alert addAction:[UIAlertAction actionWithTitle:@"设置默认启动页" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
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
// Hook UIWindow：双指双击手势
// =============================================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(fq_handleDoubleTap:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.numberOfTapsRequired = 2;
        gesture.cancelsTouchesInView = NO;
        gesture.delaysTouchesBegan = NO;
        gesture.delaysTouchesEnded = NO;
        [self addGestureRecognizer:gesture];
        NSLog(@"[FanQieNoTabs] 双指双击手势已添加");
    }
    return self;
}

%new
- (void)fq_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator prepare];
        [generator impactOccurred];
    }
    showSettingsMenu(self);
}

%end

// =============================================================
// 构造函数：初始化默认状态
// =============================================================
%ctor {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"FanQieNoTabsEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"FanQieNoTabsEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"FanQieDefaultTab"]) {
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"FanQieDefaultTab"]; // 默认书城
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    
    if (FQShouldApply()) {
        NSLog(@"[FanQieNoTabs] 加载成功（开关已开启，默认启动：%@）", FQDefaultTab() == 0 ? @"书城" : @"书架");
    } else {
        NSLog(@"[FanQieNoTabs] 加载成功（开关已关闭）");
    }
}
