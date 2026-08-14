// =============================================================
//  HongGuoFullScreen — 精简 TabBar（只保留首页和我的）
//  拦截 setViewControllers: 和 setItems:，防止系统重置
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <stdarg.h>

static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    // 写入 Documents/HongGuo.log
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

static BOOL gFiltered = NO;

// ---------- 过滤函数（只执行一次）----------
static void filterTabBar(id tabController) {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) return;
    if (gFiltered) {
        WriteLog(@"Already filtered, skip");
        return;
    }
    UITabBarController *tab = (UITabBarController *)tabController;
    NSArray *vcs = tab.viewControllers;
    if (vcs.count < 5) {
        WriteLog(@"viewControllers count < 5, skip");
        return;
    }
    WriteLog(@"Filtering... original viewControllers count: %lu", (unsigned long)vcs.count);
    // 打印原标题
    for (NSInteger i = 0; i < vcs.count; i++) {
        WriteLog(@"  [%ld] %@", (long)i, [vcs[i] tabBarItem].title ?: @"(无)");
    }
    
    // 设置新的 viewControllers（只保留索引0和4）
    NSArray *filteredVCs = @[vcs[0], vcs[4]];
    [tab setViewControllers:filteredVCs animated:NO];
    WriteLog(@"setViewControllers to %lu items", (unsigned long)filteredVCs.count);
    
    // 直接设置 tabBar.items
    NSArray *items = tab.tabBar.items;
    if (items.count >= 5) {
        [tab.tabBar setItems:@[items[0], items[4]] animated:NO];
    } else {
        // 从过滤后的 viewControllers 获取
        UITabBarItem *item0 = [filteredVCs[0] tabBarItem];
        UITabBarItem *item4 = [filteredVCs[1] tabBarItem];
        if (item0 && item4) {
            [tab.tabBar setItems:@[item0, item4] animated:NO];
        }
    }
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    tab.selectedIndex = 0;
    
    // 打印最终 items
    NSArray *finalItems = tab.tabBar.items;
    WriteLog(@"final tabBar.items count: %lu", (unsigned long)finalItems.count);
    for (NSInteger i = 0; i < finalItems.count; i++) {
        WriteLog(@"  final[%ld] %@", (long)i, [(UITabBarItem *)finalItems[i] title] ?: @"(无)");
    }
    gFiltered = YES;
    WriteLog(@"Filter completed once");
}

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    filterTabBar(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear");
    // 如果被重置，重新过滤（但只过滤一次，如果已经过滤过就不再重复）
    if (!gFiltered) {
        filterTabBar(self);
    }
}

// 拦截 setViewControllers，防止系统重置
- (void)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated {
    WriteLog(@"setViewControllers: called with %lu items", (unsigned long)viewControllers.count);
    // 如果已经过滤过，并且传入的 viewControllers 数量不是 2，则阻止
    if (gFiltered && viewControllers.count != 2) {
        WriteLog(@"Blocking setViewControllers with %lu items (already filtered)", (unsigned long)viewControllers.count);
        // 不调用原方法，但我们需要保留当前过滤后的 viewControllers
        // 直接返回，不执行 %orig
        return;
    }
    %orig;
}

- (void)setViewControllers:(NSArray *)viewControllers {
    WriteLog(@"setViewControllers: called with %lu items (no animated)", (unsigned long)viewControllers.count);
    if (gFiltered && viewControllers.count != 2) {
        WriteLog(@"Blocking setViewControllers with %lu items", (unsigned long)viewControllers.count);
        return;
    }
    %orig;
}

%end

// =============================================================
// Hook UITabBar 的 setItems，防止系统重置
// =============================================================
%hook UITabBar

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    WriteLog(@"UITabBar setItems: called with %lu items", (unsigned long)items.count);
    // 如果已经过滤过，并且传入的 items 数量不是 2，则阻止
    static BOOL gBlocking = NO;
    if (gFiltered && items.count != 2 && !gBlocking) {
        WriteLog(@"Blocking setItems with %lu items", (unsigned long)items.count);
        return;
    }
    %orig;
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
