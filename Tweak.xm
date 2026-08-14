// =============================================================
//  HongGuoFullScreen — 精简 TabBar（只保留首页和我的）
//  直接操作 tabBar.items，强制刷新
//  带完整调试日志
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>
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

// ---------- 精简 TabBar ----------
static void filterTabBarController(UITabBarController *tabController) {
    if (!tabController) return;
    
    WriteLog(@"filterTabBarController called");
    
    // 获取 viewControllers
    NSArray *vcs = tabController.viewControllers;
    WriteLog(@"viewControllers count: %lu", (unsigned long)vcs.count);
    
    if (vcs.count < 5) {
        WriteLog(@"viewControllers count < 5, skip filtering");
        return;
    }
    
    // 打印所有 viewControllers 的标题
    for (NSInteger i = 0; i < vcs.count; i++) {
        UIViewController *vc = vcs[i];
        NSString *title = vc.tabBarItem.title ?: @"(无标题)";
        WriteLog(@"  [%ld] %@ - %@", (long)i, title, NSStringFromClass([vc class]));
    }
    
    // 1. 修改 viewControllers（保留索引0和4）
    NSMutableArray *filteredVCs = [NSMutableArray array];
    [filteredVCs addObject:vcs[0]];  // 首页
    [filteredVCs addObject:vcs[4]];  // 我的
    [tabController setViewControllers:filteredVCs animated:NO];
    WriteLog(@"viewControllers filtered to %lu items", (unsigned long)filteredVCs.count);
    
    // 2. 直接修改 tabBar.items（关键！）
    NSArray *items = tabController.tabBar.items;
    WriteLog(@"tabBar.items count: %lu", (unsigned long)items.count);
    
    if (items.count >= 5) {
        NSArray *filteredItems = @[items[0], items[4]];
        [tabController.tabBar setItems:filteredItems animated:NO];
        WriteLog(@"tabBar.items filtered to %lu items", (unsigned long)filteredItems.count);
    }
    
    // 3. 强制刷新布局
    [tabController.tabBar setNeedsLayout];
    [tabController.tabBar layoutIfNeeded];
    tabController.selectedIndex = 0;
    
    WriteLog(@"TabBar filter completed");
}

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear, viewControllers count: %lu", (unsigned long)self.viewControllers.count);
    filterTabBarController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewDidAppear, viewControllers count: %lu", (unsigned long)self.viewControllers.count);
    // 检查是否被重置，如果是则重新过滤
    if (self.viewControllers.count > 2) {
        WriteLog(@"TabBar was reset, re-filtering...");
        filterTabBarController(self);
    }
}

%end

// =============================================================
// Hook SSRootViewController（延迟执行，确保加载完成）
// =============================================================
%hook SSRootViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSRootViewController viewDidAppear");
    
    // 查找 SSTabBarController
    UITabBarController *tabController = nil;
    for (UIViewController *child in self.childViewControllers) {
        if ([child isKindOfClass:NSClassFromString(@"SSTabBarController")]) {
            tabController = (UITabBarController *)child;
            WriteLog(@"Found SSTabBarController in children");
            break;
        }
    }
    
    if (tabController) {
        filterTabBarController(tabController);
    } else {
        WriteLog(@"SSTabBarController not found in children");
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
    WriteLog(@"精简Tab: 开启");
    WriteLog(@"========================================");
}
