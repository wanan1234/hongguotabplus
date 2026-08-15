// =============================================================
//  HongGuoFullScreen — 最终修正版（基于稳定版本）
//  功能：精简Tab栏 + 默认启动页 + 双指双击菜单
//  修复：高亮正确、点击切换正常、颜色自动同步
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

    // 1. 根据标题匹配高亮
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

// 强制切换到“我的”
static void forceSelectMyTab(UITabBarController *tab) {
    if (!tab || !isEnabled()) return;
    NSArray *vcs = tab.viewControllers;
    NSInteger myIndex = indexOfMyVC(vcs);
    if (myIndex == -1) return;

    // 设置正确的 selectedIndex（过滤后索引为1）
    // 但这里直接设置 selectedIndex 会触发拦截，所以直接设置 selectedViewController 并同步高亮
    if (tab.selectedViewController != vcs[myIndex]) {
        tab.selectedViewController = vcs[myIndex];
    }
    syncTabBarAppearance(tab);
}

// =============================================================
// Hook SSTabBar — 过滤 items
// =============================================================
%hook SSTabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    if (isEnabled() && items.count > 2) {
        NSArray *filtered = @[items[0], items[4]];
        %orig(filtered, animated);
        // 如果默认是我的，立即修正
        if (defaultTabIndex() == 1) {
            UIResponder *responder = (UIResponder *)self;
            while (responder && ![responder isKindOfClass:[UITabBarController class]]) {
                responder = [responder nextResponder];
            }
            if ([responder isKindOfClass:[UITabBarController class]]) {
                forceSelectMyTab((UITabBarController *)responder);
            }
        }
        return;
    }
    %orig(items, animated);
}
%end

// =============================================================
// Hook SSTabBarController — 拦截 setSelectedIndex 修正索引
// =============================================================
%hook SSTabBarController

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    UITabBarController *tab = (UITabBarController *)self;
    UITabBar *tabBar = tab.tabBar;

    // 如果已经过滤（只有2个item），进行映射
    if (isEnabled() && tabBar.items.count == 2) {
        NSInteger realIndex = -1;
        NSInteger filteredIndex = -1;

        // 判断传入的是过滤索引（0或1）还是真实索引（0~4）
        if (selectedIndex < tabBar.items.count) {
            // 传入的是过滤索引
            filteredIndex = selectedIndex;
            if (selectedIndex == 0) {
                realIndex = 0;
            } else if (selectedIndex == 1) {
                realIndex = indexOfMyVC(tab.viewControllers);
                if (realIndex == -1) realIndex = 0;
            }
        } else {
            // 传入的是真实索引
            if (selectedIndex == 0) {
                filteredIndex = 0;
                realIndex = 0;
            } else if (selectedIndex == indexOfMyVC(tab.viewControllers)) {
                filteredIndex = 1;
                realIndex = selectedIndex;
            } else {
                // 其他真实索引（如剧场）重定向到首页
                filteredIndex = 0;
                realIndex = 0;
            }
        }

        if (realIndex >= 0 && realIndex < tab.viewControllers.count) {
            // 调用原始方法切换视图（真实索引）
            %orig(realIndex);
            // 手动修正高亮
            if (filteredIndex >= 0 && filteredIndex < tabBar.items.count) {
                tabBar.selectedItem = tabBar.items[filteredIndex];
            }
            // 同步颜色
            syncTabBarAppearance(tab);
            return;
        }
    }

    // 未过滤或功能关闭，走原始逻辑
    %orig(selectedIndex);
    if (isEnabled()) {
        syncTabBarAppearance(tab);
    }
}

// viewWillAppear 中设置默认启动页
- (void)viewWillAppear:(BOOL)animated {
    if (isEnabled() && defaultTabIndex() == 1) {
        // 设置过滤索引1，会触发映射
        ((UITabBarController *)self).selectedIndex = 1;
    }
    %orig;
}

// viewDidAppear 中再次确保
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isEnabled() && defaultTabIndex() == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ((UITabBarController *)self).selectedIndex = 1;
        });
    }
}

%end

// =============================================================
// 双指双击菜单（保持不变，省略以节省篇幅）
// =============================================================
// ...（请自行保留之前的完整菜单代码）
