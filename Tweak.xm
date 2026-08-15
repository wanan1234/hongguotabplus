// =============================================================
//  HongGuoFullScreen — 纯净版 + 隐藏“我的”顶部横幅
//  功能：精简Tab栏 + 默认启动页 + 双指双击菜单 + 我的顶部自动隐藏
//  无日志、无alpha修复
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>

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

// =============================================================
// 隐藏“我的”页面顶部横幅 + 滚动归零（基于视图层级分析）
// =============================================================
static void hideTopBannerInMyPage(UIViewController *myVC) {
    if (!myVC || !isEnabled()) return;
    UIView *rootView = myVC.view;
    if (!rootView) return;

    // 1. 查找顶部横幅：FQReaderSaaSBaseImageView，高度 > 200，y=0
    UIView *bannerView = nil;
    for (UIView *sub in rootView.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"FQReaderSaaSBaseImageView"]) {
            CGRect frame = sub.frame;
            if (frame.origin.y == 0 && frame.size.height > 200) {
                bannerView = sub;
                break;
            }
        }
    }
    if (bannerView) {
        bannerView.hidden = YES;
    } else {
        // 备用：隐藏第一个高度 > 200 且 y=0 的非滚动视图
        for (UIView *sub in rootView.subviews) {
            if (sub.frame.origin.y == 0 && sub.frame.size.height > 200 &&
                ![sub isKindOfClass:[UIScrollView class]] &&
                ![NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollView"]) {
                sub.hidden = YES;
                break;
            }
        }
    }

    // 2. 查找滚动视图 SSMyUser637NestedContainerScrollView 并归零偏移
    for (UIView *sub in rootView.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollView"]) {
            if ([sub isKindOfClass:[UIScrollView class]]) {
                UIScrollView *scrollView = (UIScrollView *)sub;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [scrollView setContentOffset:CGPointMake(0, 0) animated:NO];
                });
                break;
            }
        }
    }
}

// =============================================================
// Hook SSTabBar — 过滤 items，只保留首页和我的
// =============================================================
%hook SSTabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    if (isEnabled() && items.count > 2) {
        NSArray *filtered = @[items[0], items[4]];
        %orig(filtered, animated);
        return;
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

// 拦截 setSelectedIndex，修正跳转错乱
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        NSArray *vcs = tab.viewControllers;
        if (selectedIndex < vcs.count) {
            UIViewController *targetVC = vcs[selectedIndex];
            NSString *title = targetVC.tabBarItem.title;
            if ([title isEqualToString:@"剧场"]) {
                NSInteger myIndex = indexOfMyVC(vcs);
                if (myIndex != -1) {
                    %orig(myIndex);
                    return;
                } else {
                    %orig(0);
                    return;
                }
            }
        }
    }
    %orig(selectedIndex);

    // 如果切换后选中的是“我的”，执行隐藏
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        UIViewController *selectedVC = tab.selectedViewController;
        if ([selectedVC.tabBarItem.title isEqualToString:@"我的"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                hideTopBannerInMyPage(selectedVC);
            });
        }
    }
}

// viewWillAppear 中前置设置 selectedIndex
- (void)viewWillAppear:(BOOL)animated {
    if (isEnabled() && defaultTabIndex() == 1) {
        UITabBarController *tab = (UITabBarController *)self;
        NSArray *vcs = tab.viewControllers;
        NSInteger myIndex = indexOfMyVC(vcs);
        if (myIndex != -1 && tab.selectedIndex != myIndex) {
            tab.selectedIndex = myIndex;
        }
    }
    %orig;
}

// viewDidAppear 中确保隐藏（首次加载）
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!isEnabled()) return;
    UITabBarController *tab = (UITabBarController *)self;
    UIViewController *selectedVC = tab.selectedViewController;
    if ([selectedVC.tabBarItem.title isEqualToString:@"我的"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            hideTopBannerInMyPage(selectedVC);
        });
    }
}
%end

// =============================================================
// 双指双击菜单（保持不变）
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
}
