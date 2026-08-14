// =============================================================
//  HongGuoFullScreen — 只保留首页和我的Tab
//  双指双击弹出菜单（可选），自适应布局
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>

static BOOL gApplied = NO;

%hook SSTabBarController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    
    if (gApplied) return;
    gApplied = YES;
    
    NSArray *originalVCs = self.viewControllers;
    if (originalVCs.count >= 5) {
        NSMutableArray *filtered = [NSMutableArray array];
        // 保留索引0（首页）和索引4（我的）
        [filtered addObject:originalVCs[0]];
        [filtered addObject:originalVCs[4]];
        
        // 设置新的控制器数组，不带动画
        [self setViewControllers:filtered animated:NO];
        // 强制刷新布局，系统自动分配宽度
        [self.tabBar setNeedsLayout];
        [self.tabBar layoutIfNeeded];
        // 选中首页
        self.selectedIndex = 0;
        NSLog(@"[HongGuo] TabBar filtered to only 首页 and 我的");
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // 再次确认，防止被重置
    if (self.viewControllers.count == 5) {
        NSArray *originalVCs = self.viewControllers;
        NSMutableArray *filtered = [NSMutableArray array];
        [filtered addObject:originalVCs[0]];
        [filtered addObject:originalVCs[4]];
        [self setViewControllers:filtered animated:NO];
        [self.tabBar setNeedsLayout];
        [self.tabBar layoutIfNeeded];
        self.selectedIndex = 0;
        NSLog(@"[HongGuo] TabBar re-filtered in viewDidAppear");
    }
}

%end
