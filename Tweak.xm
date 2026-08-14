// =============================================================
//  HongGuoFullScreen — 精简 TabBar（只保留首页和我的）
//  基于成功过滤版本，修正跳转问题
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <stdarg.h>

// ---------- 日志工具 ----------
static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"HongGuo.log"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:documentsDirectory]) {
        [fm createDirectoryAtPath:documentsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, msg];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    NSLog(@"[HongGuo] %@", msg);
}

// ---------- 精简函数 ----------
static void filterTabBar(id tabController) {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) {
        WriteLog(@"Not a UITabBarController, skip");
        return;
    }
    UITabBarController *tab = (UITabBarController *)tabController;
    
    NSArray *vcs = tab.viewControllers;
    if (vcs.count < 5) {
        WriteLog(@"viewControllers count < 5, skip");
        return;
    }
    WriteLog(@"viewControllers count: %lu", (unsigned long)vcs.count);
    
    // 获取原始 items
    NSArray *originalItems = tab.tabBar.items;
    for (NSInteger i = 0; i < originalItems.count; i++) {
        UITabBarItem *item = originalItems[i];
        WriteLog(@"  original[%ld] %@", (long)i, item.title ?: @"(无)");
    }
    
    // 1. 创建新的控制器数组
    UIViewController *vc0 = vcs[0];  // 首页
    UIViewController *vc4 = vcs[4];  // 我的
    
    // 重新创建 tabBarItem，确保关联正确
    // 从原始 items 复制标题和图片
    UITabBarItem *item0 = originalItems[0];
    UITabBarItem *item4 = originalItems[4];
    
    // 为控制器设置新的 tabBarItem（确保完全独立）
    vc0.tabBarItem = [[UITabBarItem alloc] initWithTitle:item0.title image:item0.image tag:0];
    vc4.tabBarItem = [[UITabBarItem alloc] initWithTitle:item4.title image:item4.image tag:1];
    
    // 2. 设置 viewControllers
    NSArray *filteredVCs = @[vc0, vc4];
    [tab setViewControllers:filteredVCs animated:NO];
    WriteLog(@"viewControllers filtered to %lu items: %@, %@", 
             (unsigned long)filteredVCs.count,
             vc0.tabBarItem.title,
             vc4.tabBarItem.title);
    
    // 3. 直接设置 tabBar.items
    [tab.tabBar setItems:@[vc0.tabBarItem, vc4.tabBarItem] animated:NO];
    WriteLog(@"tabBar.items set");
    
    // 4. 强制重置 selectedIndex
    tab.selectedIndex = 0;
    
    // 5. 强制刷新布局
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    
    // 6. 打印设置后的 items
    NSArray *finalItems = tab.tabBar.items;
    WriteLog(@"final tabBar.items count: %lu", (unsigned long)finalItems.count);
    for (NSInteger i = 0; i < finalItems.count; i++) {
        UITabBarItem *item = finalItems[i];
        WriteLog(@"  final[%ld] %@", (long)i, item.title ?: @"(无)");
    }
    
    WriteLog(@"TabBar filter completed");
}

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear");
    filterTabBar(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewDidAppear");
    filterTabBar(self);
}

%end

// =============================================================
// 构造函数
// =============================================================
%ctor {
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
}
