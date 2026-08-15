// =============================================================
//  HongGuoFullScreen — 最终版（彻底放弃 alpha）
//  只修正 frame + 设置 barTintColor + 强制重绘
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

static void fixTabBar(UITabBarController *tab) {
    if (!tab) return;
    UITabBar *tabBar = tab.tabBar;

    // 1. 修正 frame（日志显示在 viewDidLoad 时 frame 为 {{0,847},{414,49}}，正确应为底部 84 高度）
    CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
    CGFloat tabBarHeight = 84.0;
    CGRect correctFrame = CGRectMake(0, screenHeight - tabBarHeight, tabBar.frame.size.width, tabBarHeight);
    if (!CGRectEqualToRect(tabBar.frame, correctFrame)) {
        tabBar.frame = correctFrame;
    }

    // 2. 设置 barTintColor（触发重绘，不修改 alpha）
    UIViewController *selected = tab.selectedViewController;
    if (selected) {
        UIColor *bgColor = selected.view.backgroundColor;
        if (!bgColor) {
            CGColorRef layerColor = selected.view.layer.backgroundColor;
            if (layerColor) bgColor = [UIColor colorWithCGColor:layerColor];
        }
        if (bgColor) {
            tabBar.barTintColor = bgColor;
            tabBar.translucent = NO;
        }
    }

    // 3. 刷新背景视图
    id backgroundView = [tabBar valueForKey:@"_backgroundView"];
    if (backgroundView && [backgroundView respondsToSelector:@selector(setNeedsDisplay)]) {
        [backgroundView performSelector:@selector(setNeedsDisplay)];
    }

    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
}

// =============================================================
// Hook SSTabBar
// =============================================================
%hook SSTabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    if (isEnabled() && items.count > 2) {
        NSArray *filtered = @[items[0], items[4]];
        %orig(filtered, animated);
        UIResponder *responder = self;
        while (responder && ![responder isKindOfClass:[UITabBarController class]]) {
            responder = [responder nextResponder];
        }
        if ([responder isKindOfClass:[UITabBarController class]]) {
            fixTabBar((UITabBarController *)responder);
        }
        return;
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController（完全移除 alpha 相关操作）
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        if (tab.selectedIndex >= tab.viewControllers.count) {
            tab.selectedIndex = 0;
        }
        fixTabBar(tab);
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
    if (isEnabled()) {
        fixTabBar((UITabBarController *)self);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!isEnabled()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UITabBarController *tab = (UITabBarController *)self;
            fixTabBar(tab);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                fixTabBar(tab);
            });
        });
    });
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (isEnabled()) {
        fixTabBar((UITabBarController *)self);
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        NSArray *vcs = tab.viewControllers;
        if (selectedIndex >= vcs.count) {
            %orig(0);
            return;
        }
        UIViewController *targetVC = vcs[selectedIndex];
        NSString *title = targetVC.tabBarItem.title;
        if ([title isEqualToString:@"剧场"]) {
            NSInteger myIndex = indexOfMyVC(vcs);
            if (myIndex != -1) {
                %orig(myIndex);
                fixTabBar(tab);
                return;
            } else {
                %orig(0);
                return;
            }
        }
    }
    %orig(selectedIndex);
    if (isEnabled()) {
        fixTabBar((UITabBarController *)self);
    }
}
%end

// =============================================================
// 双指双击菜单（保持不变）
// =============================================================
// ... (菜单代码与之前相同，省略)
