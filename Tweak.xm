// =============================================================
//  HongGuoFullScreen — 诊断版 v2（精确隐藏顶部横幅）
//  功能：精简Tab栏 + 默认启动页 + 双指双击菜单 + 隐藏顶部（调试中）
//  诊断日志：进入“我的”页面时自动打印视图树到 Documents/viewHierarchy.log
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
// 诊断：递归打印视图层级（含 hidden、frame、class、text）
// =============================================================
static void dumpViewHierarchy(UIView *view, NSInteger depth, NSMutableString *output) {
    if (!view) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *classStr = NSStringFromClass([view class]);
    NSString *frameStr = NSStringFromCGRect(view.frame);
    NSString *hiddenStr = view.hidden ? @"YES" : @"NO";
    NSString *text = @"";
    if ([view isKindOfClass:[UILabel class]]) {
        text = [(UILabel *)view text] ?: @"";
    } else if ([view isKindOfClass:[UIButton class]]) {
        text = [(UIButton *)view titleForState:UIControlStateNormal] ?: @"";
    }
    [output appendFormat:@"%@%@ frame=%@ hidden=%@ text=%@\n", indent, classStr, frameStr, hiddenStr, text];
    for (UIView *sub in view.subviews) {
        dumpViewHierarchy(sub, depth + 1, output);
    }
}

static void logMyPageViewHierarchy(UIViewController *myVC) {
    if (!myVC) return;
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"===== 诊断“我的”页面视图层级 =====\n控制器类: %@\nview frame: %@\n",
     NSStringFromClass([myVC class]), NSStringFromCGRect(myVC.view.frame)];
    dumpViewHierarchy(myVC.view, 0, output);
    [output appendString:@"===== 诊断结束 =====\n"];

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = [paths firstObject];
    NSString *filePath = [docPath stringByAppendingPathComponent:@"viewHierarchy.log"];
    [output writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"[HongGuo] 视图层级已保存至: %@", filePath);
}

// =============================================================
// 精确隐藏顶部横幅 + 占位视图 + 滚动归零
// =============================================================
static void hideTopBannerInMyPage(UIViewController *myVC) {
    if (!myVC || !isEnabled()) return;
    UIView *rootView = myVC.view;
    if (!rootView) return;

    // 1. 查找并隐藏可见的顶部横幅（FQReaderSaaSBaseImageView，y=0，高度>200，hidden=NO）
    UIView *bannerView = nil;
    for (UIView *sub in rootView.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"FQReaderSaaSBaseImageView"]) {
            CGRect frame = sub.frame;
            if (frame.origin.y == 0 && frame.size.height > 200 && !sub.hidden) {
                bannerView = sub;
                break;
            }
        }
    }
    if (bannerView) {
        bannerView.hidden = YES;
        NSLog(@"[HongGuo] 已隐藏可见横幅: %@", NSStringFromCGRect(bannerView.frame));
    } else {
        NSLog(@"[HongGuo] 未找到可见横幅，尝试隐藏第一个高度>200的视图");
        for (UIView *sub in rootView.subviews) {
            if (sub.frame.origin.y == 0 && sub.frame.size.height > 200 &&
                ![sub isKindOfClass:[UIScrollView class]] &&
                ![NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollView"]) {
                sub.hidden = YES;
                NSLog(@"[HongGuo] 备用隐藏: %@", NSStringFromClass([sub class]));
                break;
            }
        }
    }

    // 2. 查找滚动视图 SSMyUser637NestedContainerScrollView
    UIScrollView *scrollView = nil;
    for (UIView *sub in rootView.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollView"]) {
            if ([sub isKindOfClass:[UIScrollView class]]) {
                scrollView = (UIScrollView *)sub;
                break;
            }
        }
    }

    if (scrollView) {
        // 2.1 隐藏滚动内容中的顶部占位视图（高度约91，无文本）
        for (UIView *sub in scrollView.subviews) {
            if ([NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollContentView"]) {
                if (sub.subviews.count > 0) {
                    UIView *firstChild = sub.subviews[0];
                    if (firstChild.frame.size.height >= 80 && firstChild.frame.size.height <= 100) {
                        // 检查是否包含有效文本
                        BOOL hasText = NO;
                        for (UIView *gc in firstChild.subviews) {
                            if ([gc isKindOfClass:[UILabel class]]) {
                                UILabel *label = (UILabel *)gc;
                                if (label.text.length > 0 && ![label.text isEqualToString:@"(空)"]) {
                                    hasText = YES;
                                    break;
                                }
                            }
                        }
                        if (!hasText) {
                            firstChild.hidden = YES;
                            NSLog(@"[HongGuo] 隐藏滚动内容内顶部占位视图");
                        }
                    }
                }
                break;
            }
        }

        // 2.2 调整滚动视图的 contentOffset 和 contentInset
        dispatch_async(dispatch_get_main_queue(), ^{
            // 归零偏移
            [scrollView setContentOffset:CGPointMake(0, 0) animated:NO];
            // 重置 contentInset 的 top（防止系统自动添加）
            UIEdgeInsets insets = scrollView.contentInset;
            if (insets.top != 0) {
                insets.top = 0;
                scrollView.contentInset = insets;
            }
            NSLog(@"[HongGuo] 滚动视图偏移归零，contentInset.top=0");
        });
    } else {
        NSLog(@"[HongGuo] 未找到滚动视图");
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

    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        UIViewController *selectedVC = tab.selectedViewController;
        if ([selectedVC.tabBarItem.title isEqualToString:@"我的"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                hideTopBannerInMyPage(selectedVC);
                logMyPageViewHierarchy(selectedVC);  // 诊断
            });
        }
    }
}

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

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!isEnabled()) return;
    UITabBarController *tab = (UITabBarController *)self;
    UIViewController *selectedVC = tab.selectedViewController;
    if ([selectedVC.tabBarItem.title isEqualToString:@"我的"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            hideTopBannerInMyPage(selectedVC);
            logMyPageViewHierarchy(selectedVC);  // 诊断
        });
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!isEnabled()) return;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UITabBarController *tab = (UITabBarController *)self;
        UIViewController *selectedVC = tab.selectedViewController;
        if ([selectedVC.tabBarItem.title isEqualToString:@"我的"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                logMyPageViewHierarchy(selectedVC);
            });
        }
    });
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
