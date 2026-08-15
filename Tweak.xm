// =============================================================
//  HongGuoFullScreen — 最终版（白色Tab + 正常切换）
//  参考用户提供的白色版本，只添加索引映射以修复点击错乱
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
// 强制切换到“我的”并同步TabBar高亮（来自白色版本）
// =============================================================
static void forceSelectMyTab(UITabBarController *tab) {
    if (!tab || !isEnabled()) return;
    NSArray *vcs = tab.viewControllers;
    NSInteger myIndex = indexOfMyVC(vcs);
    if (myIndex == -1) return;
    
    if (tab.selectedViewController != vcs[myIndex]) {
        tab.selectedViewController = vcs[myIndex];
    }
    
    UITabBar *tabBar = tab.tabBar;
    for (UITabBarItem *item in tabBar.items) {
        if ([item.title isEqualToString:@"我的"]) {
            if (tabBar.selectedItem != item) {
                tabBar.selectedItem = item;
            }
            break;
        }
    }
    
    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
}

// 强制切换到首页（辅助）
static void forceSelectHomeTab(UITabBarController *tab) {
    if (!tab || !isEnabled()) return;
    NSArray *vcs = tab.viewControllers;
    if (vcs.count == 0) return;
    UIViewController *homeVC = vcs[0];
    if (tab.selectedViewController != homeVC) {
        tab.selectedViewController = homeVC;
    }
    UITabBar *tabBar = tab.tabBar;
    if (tabBar.items.count > 0) {
        if (tabBar.selectedItem != tabBar.items[0]) {
            tabBar.selectedItem = tabBar.items[0];
        }
    }
    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
}

// 根据过滤索引切换（0=首页，1=我的）
static void switchToFilteredIndex(UITabBarController *tab, NSInteger filteredIndex) {
    if (filteredIndex == 0) {
        forceSelectHomeTab(tab);
    } else if (filteredIndex == 1) {
        forceSelectMyTab(tab);
    }
}

// =============================================================
// Hook SSTabBar — 过滤 items（与白色版本一致）
// =============================================================
%hook SSTabBar
- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    if (isEnabled() && items.count > 2) {
        NSArray *filtered = @[items[0], items[4]];
        %orig(filtered, animated);
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
// Hook SSTabBarController — 添加索引映射
// =============================================================
%hook SSTabBarController

// 拦截 setSelectedIndex，映射索引
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        UITabBar *tabBar = tab.tabBar;
        // 如果已经过滤（只有2个item），进行映射
        if (tabBar.items.count == 2) {
            NSInteger filteredIndex = -1;
            // 判断传入的是过滤索引还是真实索引
            if (selectedIndex < tabBar.items.count) {
                // 过滤索引
                filteredIndex = selectedIndex;
            } else {
                // 真实索引
                if (selectedIndex == 0) filteredIndex = 0;
                else if (selectedIndex == indexOfMyVC(tab.viewControllers)) filteredIndex = 1;
                else filteredIndex = (defaultTabIndex() == 1) ? 1 : 0; // 其他重定向
            }
            if (filteredIndex >= 0 && filteredIndex < 2) {
                switchToFilteredIndex(tab, filteredIndex);
                return; // 不调用原始方法
            }
        }
    }
    %orig(selectedIndex);
}

// viewWillAppear
- (void)viewWillAppear:(BOOL)animated {
    if (isEnabled() && defaultTabIndex() == 1) {
        forceSelectMyTab((UITabBarController *)self);
    }
    %orig;
}

// viewDidAppear 确保
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isEnabled() && defaultTabIndex() == 1) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            forceSelectMyTab((UITabBarController *)self);
        });
    }
}

%end

// =============================================================
// 双指双击菜单（保持不变）
// =============================================================
// （此处粘贴您之前的完整菜单代码，以免遗漏）
// ...
