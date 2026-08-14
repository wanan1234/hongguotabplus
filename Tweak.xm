// =============================================================
//  HongGuoFullScreen — 精简 TabBar（只保留首页和我的）
//  修正：点击“我的”跳转到“剧场”的问题
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
    
    // 获取原始 items 标题
    NSArray *originalItems = tab.tabBar.items;
    for (NSInteger i = 0; i < originalItems.count; i++) {
        UITabBarItem *item = originalItems[i];
        WriteLog(@"  original[%ld] %@", (long)i, item.title ?: @"(无)");
    }
    
    // 1. 过滤 viewControllers（保留索引0和4）
    NSArray *filteredVCs = @[vcs[0], vcs[4]];
    [tab setViewControllers:filteredVCs animated:NO];
    WriteLog(@"viewControllers filtered to %lu items: %@, %@", 
             (unsigned long)filteredVCs.count,
             [vcs[0] tabBarItem].title,
             [vcs[4] tabBarItem].title);
    
    // 2. 直接设置 tabBar.items
    NSArray *items = tab.tabBar.items;
    if (items.count >= 5) {
        NSArray *filteredItems = @[items[0], items[4]];
        [tab.tabBar setItems:filteredItems animated:NO];
        WriteLog(@"tabBar.items set to %lu items", (unsigned long)filteredItems.count);
    } else {
        // 从 viewControllers 获取 tabBarItem
        UITabBarItem *item0 = [vcs[0] tabBarItem];
        UITabBarItem *item4 = [vcs[4] tabBarItem];
        if (item0 && item4) {
            [tab.tabBar setItems:@[item0, item4] animated:NO];
            WriteLog(@"tabBar.items set from vcs");
        }
    }
    
    // 3. 关键：强制重置 selectedIndex
    tab.selectedIndex = 0;
    
    // 4. 强制刷新
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    
    // 5. 打印设置后的 items
    NSArray *finalItems = tab.tabBar.items;
    WriteLog(@"final tabBar.items count: %lu", (unsigned long)finalItems.count);
    for (NSInteger i = 0; i < finalItems.count; i++) {
        UITabBarItem *item = finalItems[i];
        WriteLog(@"  final[%ld] %@", (long)i, item.title ?: @"(无)");
    }
    
    WriteLog(@"TabBar filter completed");
}

// ---------- 在 viewDidLayoutSubviews 中执行（限流）----------
static NSTimeInterval lastFilterTime = 0;

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    // 在 viewDidLoad 中立即执行，尽早过滤
    filterTabBar(self);
}

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

- (void)viewDidLayoutSubviews {
    %orig;
    // 布局变化后重新执行（但限流）
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastFilterTime > 0.2) {
        lastFilterTime = now;
        filterTabBar(self);
    }
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
