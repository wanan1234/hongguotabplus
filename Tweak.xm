// =============================================================
//  HongGuoFullScreen — 精简 TabBar（只保留首页和我的）
//  极简版，只操作 tabBar.items，带调试日志
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

// ---------- 精简函数（使用 id 类型避免编译问题）----------
static void filterTabBar(id tabController) {
    if (!tabController) return;
    
    // 安全类型检查
    if (![tabController isKindOfClass:[UITabBarController class]]) {
        WriteLog(@"Not a UITabBarController, skip");
        return;
    }
    
    UITabBarController *tab = (UITabBarController *)tabController;
    
    // 获取 tabBar.items
    NSArray *items = tab.tabBar.items;
    WriteLog(@"tabBar.items count: %lu", (unsigned long)items.count);
    
    if (items.count < 5) {
        WriteLog(@"items count < 5, skip");
        return;
    }
    
    // 打印每个 item 的标题
    for (NSInteger i = 0; i < items.count; i++) {
        UITabBarItem *item = items[i];
        WriteLog(@"  [%ld] %@", (long)i, item.title ?: @"(无标题)");
    }
    
    // 只保留索引0和4（首页和我的）
    NSArray *filteredItems = @[items[0], items[4]];
    WriteLog(@"Filtered to: %@, %@", items[0].title, items[4].title);
    
    // 设置新的 items（不带动画）
    [tab.tabBar setItems:filteredItems animated:NO];
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    
    // 也修改 viewControllers 保持一致性
    NSArray *vcs = tab.viewControllers;
    if (vcs.count >= 5) {
        NSArray *filteredVCs = @[vcs[0], vcs[4]];
        [tab setViewControllers:filteredVCs animated:NO];
        WriteLog(@"viewControllers also filtered");
    }
    
    tab.selectedIndex = 0;
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
    // 检查是否被重置
    if (self.tabBar.items.count > 2) {
        WriteLog(@"TabBar was reset, re-filtering...");
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
