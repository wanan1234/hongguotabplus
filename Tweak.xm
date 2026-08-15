// =============================================================
//  HongGuoFullScreen — 最终纯净版（直接过滤 ViewControllers）
//  功能：精简Tab栏（首页、我的）+ 默认启动页 + 双指双击菜单
//  原理：将 viewControllers 替换为只包含首页和我的，selectedIndex 自动正确
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>

static BOOL isEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreenEnabled"];
}

static NSInteger defaultTabIndex() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"HongGuoDefaultTab"];
}

// =============================================================
// 获取当前页面背景色（用于 TabBar 颜色同步）
// =============================================================
static UIColor *getCurrentPageBackgroundColor(UITabBarController *tab) {
    UIViewController *selected = tab.selectedViewController;
    if (!selected) return nil;
    UIColor *color = selected.view.backgroundColor;
    if (color) return color;
    CGColorRef layerColor = selected.view.layer.backgroundColor;
    if (layerColor) return [UIColor colorWithCGColor:layerColor];
    return nil;
}

// =============================================================
// 同步 TabBar 高亮和颜色
// =============================================================
static void syncTabBarAppearance(UITabBarController *tab) {
    if (!tab || !isEnabled()) return;
    UITabBar *tabBar = tab.tabBar;
    UIViewController *selected = tab.selectedViewController;
    if (!selected) return;

    // 1. 根据标题匹配高亮（此时 items 只有2个，索引即0/1）
    NSString *title = selected.tabBarItem.title;
    for (UITabBarItem *item in tabBar.items) {
        if ([item.title isEqualToString:title]) {
            if (tabBar.selectedItem != item) {
                tabBar.selectedItem = item;
            }
            break;
        }
    }

    // 2. 设置背景色
    UIColor *bgColor = getCurrentPageBackgroundColor(tab);
    if (bgColor) {
        tabBar.barTintColor = bgColor;
        tabBar.translucent = NO;
    }

    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
}

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

// 在 viewDidLoad 中替换 viewControllers，只保留首页和我的
- (void)viewDidLoad {
    %orig;
    if (!isEnabled()) return;

    UITabBarController *tab = (UITabBarController *)self;
    NSArray *vcs = tab.viewControllers;
    if (vcs.count < 5) return; // 安全保护

    // 提取首页（索引0）和我的（索引4）
    UIViewController *homeVC = vcs[0];
    UIViewController *myVC = vcs[4];
    if (homeVC && myVC) {
        tab.viewControllers = @[homeVC, myVC];
        // 如果默认启动是我的，选中索引1
        if (defaultTabIndex() == 1) {
            tab.selectedIndex = 1;
        } else {
            tab.selectedIndex = 0;
        }
        syncTabBarAppearance(tab);
    }
}

// 拦截 setSelectedIndex，确保索引正确（此时只有0或1）
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    UITabBarController *tab = (UITabBarController *)self;
    // 如果已经过滤（viewControllers.count==2），索引范围0~1
    if (isEnabled() && tab.viewControllers.count == 2) {
        if (selectedIndex < 0 || selectedIndex >= tab.viewControllers.count) {
            // 如果传入非法索引（如4），强制修正为0或1
            selectedIndex = (defaultTabIndex() == 1) ? 1 : 0;
        }
        %orig(selectedIndex);
        syncTabBarAppearance(tab);
        return;
    }
    %orig(selectedIndex);
    if (isEnabled()) {
        syncTabBarAppearance(tab);
    }
}

// viewWillAppear 中再次确保默认页
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!isEnabled()) return;
    UITabBarController *tab = (UITabBarController *)self;
    if (tab.viewControllers.count == 2) {
        NSInteger targetIndex = (defaultTabIndex() == 1) ? 1 : 0;
        if (tab.selectedIndex != targetIndex) {
            tab.selectedIndex = targetIndex;
            syncTabBarAppearance(tab);
        }
    }
}

// viewDidAppear 中再次确保（防止系统重置）
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!isEnabled()) return;
    UITabBarController *tab = (UITabBarController *)self;
    if (tab.viewControllers.count == 2) {
        NSInteger targetIndex = (defaultTabIndex() == 1) ? 1 : 0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (tab.selectedIndex != targetIndex) {
                tab.selectedIndex = targetIndex;
                syncTabBarAppearance(tab);
            }
        });
    }
}

%end

// =============================================================
// 双指双击菜单（保持不变，此处省略，复用之前的）
// =============================================================
// ...（此处省略，与之前完全相同，请复制完整版）
