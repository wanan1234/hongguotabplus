// =============================================================
//  HongGuoFullScreen — 最终版（文本匹配隐藏 + 强制调整）
//  功能：精简Tab栏 + 默认启动页 + 双指双击菜单 + 彻底移除顶部横幅
//  诊断日志保留
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
// 诊断：递归打印视图层级
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
// 辅助：递归获取所有子视图
// =============================================================
static void getAllSubviews(UIView *view, NSMutableArray *array) {
    [array addObject:view];
    for (UIView *sub in view.subviews) {
        getAllSubviews(sub, array);
    }
}

// =============================================================
// 暴力调整布局（隐藏所有横幅 + 强制移动UICollectionView）
// =============================================================
static void hideTopBannerInMyPage(UIViewController *myVC) {
    if (!myVC || !isEnabled()) return;
    UIView *rootView = myVC.view;
    if (!rootView) return;

    // ---- 1. 隐藏所有包含特定文本的视图及其父视图 ----
    NSMutableArray *allViews = [NSMutableArray array];
    getAllSubviews(rootView, allViews);
    for (UIView *view in allViews) {
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)view;
            NSString *text = label.text;
            if ([text containsString:@"爆款"] || [text containsString:@"上新"] || [text containsString:@"娘为小师妹撑腰"]) {
                // 找到最近的父视图，高度大于100的隐藏
                UIView *parent = view.superview;
                while (parent) {
                    if (parent.frame.size.height > 80 && parent != rootView) {
                        parent.hidden = YES;
                        NSLog(@"[HongGuo] 隐藏包含文本的父视图: %@", NSStringFromClass([parent class]));
                        break;
                    }
                    parent = parent.superview;
                }
            }
        }
    }

    // ---- 2. 隐藏所有高度 > 200 的 FQReaderSaaSBaseImageView ----
    for (UIView *view in allViews) {
        if ([NSStringFromClass([view class]) isEqualToString:@"FQReaderSaaSBaseImageView"]) {
            if (view.frame.size.height > 200) {
                view.hidden = YES;
                NSLog(@"[HongGuo] 隐藏大图: %@", NSStringFromCGRect(view.frame));
            }
        }
    }

    // ---- 3. 查找滚动视图 ----
    UIScrollView *scrollView = nil;
    for (UIView *sub in rootView.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollView"]) {
            if ([sub isKindOfClass:[UIScrollView class]]) {
                scrollView = (UIScrollView *)sub;
                break;
            }
        }
    }
    if (!scrollView) {
        NSLog(@"[HongGuo] 未找到滚动视图");
        return;
    }

    // ---- 4. 强制调整滚动视图的 contentInset 和 offset ----
    UIEdgeInsets insets = scrollView.contentInset;
    if (insets.top != 0) {
        insets.top = 0;
        scrollView.contentInset = insets;
        NSLog(@"[HongGuo] 重置 contentInset.top = 0");
    }
    [scrollView setContentOffset:CGPointMake(0, 0) animated:NO];

    // ---- 5. 找到用户信息UICollectionView并强制设y=0 ----
    for (UIView *sub in scrollView.subviews) {
        if ([NSStringFromClass([sub class]) isEqualToString:@"SSMyUser637NestedContainerScrollContentView"]) {
            for (UIView *child in sub.subviews) {
                if ([child isKindOfClass:[UICollectionView class]]) {
                    CGRect frame = child.frame;
                    if (frame.origin.y != 0) {
                        frame.origin.y = 0;
                        child.frame = frame;
                        NSLog(@"[HongGuo] 已设置UICollectionView frame.y = 0");
                    }
                    // 同时检查该collectionView的内容偏移是否可能影响
                    if ([child isKindOfClass:[UIScrollView class]]) {
                        [(UIScrollView *)child setContentOffset:CGPointMake(0, 0) animated:NO];
                    }
                    break;
                }
            }
            break;
        }
    }

    // ---- 6. 多次延迟刷新 ----
    dispatch_async(dispatch_get_main_queue(), ^{
        [scrollView setContentOffset:CGPointMake(0, 0) animated:NO];
        [scrollView setNeedsLayout];
        [scrollView layoutIfNeeded];
        NSLog(@"[HongGuo] 第1次刷新");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [scrollView setContentOffset:CGPointMake(0, 0) animated:NO];
        [scrollView layoutIfNeeded];
        NSLog(@"[HongGuo] 第2次刷新");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [scrollView setContentOffset:CGPointMake(0, 0) animated:NO];
        [scrollView layoutIfNeeded];
        NSLog(@"[HongGuo] 第3次刷新");
    });
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
                logMyPageViewHierarchy(selectedVC);
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                hideTopBannerInMyPage(selectedVC);
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
            logMyPageViewHierarchy(selectedVC);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            hideTopBannerInMyPage(selectedVC);
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
