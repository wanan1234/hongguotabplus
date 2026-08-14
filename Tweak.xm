// =============================================================
//  HongGuoFullScreen — 精简 TabBar（参考番茄小说方案）
//  使用 UITabBarController 的 API 避免前向声明问题
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <stdarg.h>

static void WriteLog(NSString *format, ...) {
    // ... 日志函数不变 ...
}

static BOOL gFiltered = NO;

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

static void filterTabBar(id tabController) {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) return;
    if (gFiltered) return;
    
    UITabBarController *tab = (UITabBarController *)tabController;
    NSArray *vcs = tab.viewControllers;
    if (vcs.count < 5) return;
    
    WriteLog(@"Filtering... original viewControllers count: %lu", (unsigned long)vcs.count);
    for (NSInteger i = 0; i < vcs.count; i++) {
        WriteLog(@"  [%ld] %@", (long)i, [vcs[i] tabBarItem].title ?: @"(无)");
    }
    
    NSArray *filteredVCs = @[vcs[0], vcs[4]];
    [tab setViewControllers:filteredVCs animated:NO];
    
    NSArray *items = tab.tabBar.items;
    if (items.count >= 5) {
        [tab.tabBar setItems:@[items[0], items[4]] animated:NO];
    }
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    tab.selectedIndex = 0;
    
    gFiltered = YES;
    WriteLog(@"Filter completed");
}

%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    filterTabBar(self);
}

// 拦截 setSelectedIndex
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"setSelectedIndex called: %ld", (long)selectedIndex);
    
    // 强制转换为 UITabBarController 以使用其 API
    UITabBarController *tab = (UITabBarController *)self;
    
    if (gFiltered) {
        NSArray *vcs = tab.viewControllers;
        WriteLog(@"current viewControllers count: %lu", (unsigned long)vcs.count);
        
        if (selectedIndex >= vcs.count) {
            selectedIndex = 0;
            WriteLog(@"Index out of bounds, redirected to 0");
        }
        
        if (selectedIndex < vcs.count) {
            UIViewController *targetVC = vcs[selectedIndex];
            NSString *title = targetVC.tabBarItem.title;
            WriteLog(@"Target VC title: %@", title ?: @"(无)");
            
            if ([title isEqualToString:@"剧场"] || 
                [title isEqualToString:@"商城"] || 
                [title isEqualToString:@"福利"]) {
                NSInteger myIndex = indexOfMyVC(vcs);
                if (myIndex != -1) {
                    selectedIndex = myIndex;
                    WriteLog(@"Redirected to '我的' index: %ld", (long)myIndex);
                } else {
                    selectedIndex = 0;
                    WriteLog(@"Redirected to index 0");
                }
            }
        }
    }
    
    %orig(selectedIndex);
    WriteLog(@"setSelectedIndex completed to: %ld", (long)selectedIndex);
}

%end

%ctor {
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
}
