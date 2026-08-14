// =============================================================
//  HongGuoFullScreen — 精简 TabBar（只保留首页和我的）
//  Hook UITabBarController，通过 Bundle ID 限制生效范围
//  拦截 setItems 和 setViewControllers，防止重置
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <stdarg.h>

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

static BOOL gFiltered = NO;
static BOOL isHongGuo() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.phoenix.video"];
}

// ---------- 过滤函数 ----------
static void filterTabBar(id tabController) {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) return;
    if (!isHongGuo()) return;
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
    for (NSInteger i = 0; i < vcs.count; i++) {
        UIViewController *vc = vcs[i];
        UITabBarItem *item = [vc tabBarItem];
        WriteLog(@"  [%ld] %@", (long)i, item.title ?: @"(无)");
    }
    
    // 1. 过滤 viewControllers（保留索引0和4）
    NSArray *filteredVCs = @[vcs[0], vcs[4]];
    [tab setViewControllers:filteredVCs animated:NO];
    WriteLog(@"setViewControllers to %lu items", (unsigned long)filteredVCs.count);
    
    // 2. 过滤 tabBar.items
    NSArray *items = tab.tabBar.items;
    if (items.count >= 5) {
        NSArray *filteredItems = @[items[0], items[4]];
        [tab.tabBar setItems:filteredItems animated:NO];
        WriteLog(@"tabBar.items set to %lu items", (unsigned long)filteredItems.count);
    } else {
        UITabBarItem *item0 = [filteredVCs[0] tabBarItem];
        UITabBarItem *item4 = [filteredVCs[1] tabBarItem];
        if (item0 && item4) {
            [tab.tabBar setItems:@[item0, item4] animated:NO];
            WriteLog(@"tabBar.items set from vcs");
        }
    }
    
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    tab.selectedIndex = 0;
    
    NSArray *finalItems = tab.tabBar.items;
    WriteLog(@"final tabBar.items count: %lu", (unsigned long)finalItems.count);
    for (NSInteger i = 0; i < finalItems.count; i++) {
        UITabBarItem *item = finalItems[i];
        WriteLog(@"  final[%ld] %@", (long)i, item.title ?: @"(无)");
    }
    gFiltered = YES;
    WriteLog(@"Filter completed once");
}

// =============================================================
// Hook UITabBarController（通用，但限制 Bundle ID）
// =============================================================
%hook UITabBarController

- (void)viewDidLoad {
    %orig;
    if (isHongGuo()) {
        WriteLog(@"UITabBarController viewDidLoad");
        filterTabBar(self);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (isHongGuo() && !gFiltered) {
        WriteLog(@"UITabBarController viewWillAppear");
        filterTabBar(self);
    }
}

// 拦截 setViewControllers，防止系统重置
- (void)setViewControllers:(NSArray *)viewControllers animated:(BOOL)animated {
    if (isHongGuo() && gFiltered) {
        WriteLog(@"setViewControllers:animated called with %lu items", (unsigned long)viewControllers.count);
        if (viewControllers.count != 2) {
            WriteLog(@"Blocking setViewControllers with %lu items", (unsigned long)viewControllers.count);
            return;
        }
    }
    %orig;
}

- (void)setViewControllers:(NSArray *)viewControllers {
    if (isHongGuo() && gFiltered) {
        WriteLog(@"setViewControllers called with %lu items", (unsigned long)viewControllers.count);
        if (viewControllers.count != 2) {
            WriteLog(@"Blocking setViewControllers with %lu items", (unsigned long)viewControllers.count);
            return;
        }
    }
    %orig;
}

// 拦截 setSelectedIndex，重定向到“我的”（参考番茄小说）
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (isHongGuo() && gFiltered) {
        WriteLog(@"setSelectedIndex called: %ld", (long)selectedIndex);
        NSArray *vcs = self.viewControllers;
        if (vcs.count == 2) {
            // 确保索引不越界
            if (selectedIndex >= vcs.count) {
                selectedIndex = 0;
                WriteLog(@"Index out of bounds, redirected to 0");
            }
            // 如果试图选中“剧场”“商城”“福利”，重定向到“我的”（索引1）
            if (selectedIndex < vcs.count) {
                UIViewController *targetVC = vcs[selectedIndex];
                NSString *title = [[targetVC tabBarItem] title];
                WriteLog(@"Target title: %@", title ?: @"(无)");
                if ([title isEqualToString:@"剧场"] || [title isEqualToString:@"商城"] || [title isEqualToString:@"福利"]) {
                    // 查找“我的”的索引
                    NSInteger myIndex = -1;
                    for (NSInteger i = 0; i < vcs.count; i++) {
                        UIViewController *vc = vcs[i];
                        if ([[[vc tabBarItem] title] isEqualToString:@"我的"]) {
                            myIndex = i;
                            break;
                        }
                    }
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
    }
    %orig(selectedIndex);
}

%end

// =============================================================
// Hook UITabBar 的 setItems，防止系统重置
// =============================================================
%hook UITabBar

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    if (isHongGuo() && gFiltered) {
        WriteLog(@"UITabBar setItems:animated called with %lu items", (unsigned long)items.count);
        if (items.count != 2) {
            WriteLog(@"Blocking setItems with %lu items", (unsigned long)items.count);
            return;
        }
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
