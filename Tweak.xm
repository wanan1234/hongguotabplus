// =============================================================
//  HongGuoFullScreen — 精简 TabBar（使用 KVC 解决编译问题）
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

// ---------- 辅助函数 ----------
static NSArray *filterViewControllers(NSArray *vcs) {
    if (vcs.count == 0) return vcs;
    NSMutableArray *result = [NSMutableArray array];
    for (UIViewController *vc in vcs) {
        UITabBarItem *item = [vc tabBarItem];
        NSString *title = item.title;
        if ([title isEqualToString:@"首页"] || [title isEqualToString:@"我的"]) {
            [result addObject:vc];
        }
    }
    return result;
}

static NSArray *filterTabBarItems(NSArray *items) {
    if (items.count == 0) return items;
    NSMutableArray *result = [NSMutableArray array];
    for (UITabBarItem *item in items) {
        NSString *title = item.title;
        if ([title isEqualToString:@"首页"] || [title isEqualToString:@"我的"]) {
            [result addObject:item];
        }
    }
    return result;
}

// ---------- 过滤函数（使用 KVC）----------
static void filterTabBarController(id tabController) {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) return;
    UITabBarController *tab = (UITabBarController *)tabController;
    
    // 使用 KVC 访问 viewControllers
    NSArray *vcs = [tab valueForKey:@"viewControllers"];
    if (vcs.count < 5) {
        WriteLog(@"viewControllers count < 5, skip");
        return;
    }
    WriteLog(@"Filtering... original viewControllers count: %lu", (unsigned long)vcs.count);
    for (NSInteger i = 0; i < vcs.count; i++) {
        UITabBarItem *item = [vcs[i] tabBarItem];
        WriteLog(@"  [%ld] %@", (long)i, item.title ?: @"(无)");
    }
    
    // 过滤 viewControllers
    NSArray *filteredVCs = filterViewControllers(vcs);
    if (filteredVCs.count != 2) {
        WriteLog(@"Filtered viewControllers count is %lu, expected 2", (unsigned long)filteredVCs.count);
        return;
    }
    [tab setViewControllers:filteredVCs animated:NO];
    WriteLog(@"viewControllers set to %lu items", (unsigned long)filteredVCs.count);
    
    // 过滤 tabBar.items
    NSArray *items = tab.tabBar.items;
    if (items.count >= 5) {
        NSArray *filteredItems = filterTabBarItems(items);
        if (filteredItems.count == 2) {
            [tab.tabBar setItems:filteredItems animated:NO];
            WriteLog(@"tabBar.items set to %lu items", (unsigned long)filteredItems.count);
        }
    } else {
        // 从 viewControllers 获取
        UITabBarItem *item0 = [[filteredVCs objectAtIndex:0] tabBarItem];
        UITabBarItem *item1 = [[filteredVCs objectAtIndex:1] tabBarItem];
        if (item0 && item1) {
            [tab.tabBar setItems:@[item0, item1] animated:NO];
            WriteLog(@"tabBar.items set from viewControllers");
        }
    }
    
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    [tab setSelectedIndex:0];
    
    NSArray *finalItems = tab.tabBar.items;
    WriteLog(@"final tabBar.items count: %lu", (unsigned long)finalItems.count);
    for (NSInteger i = 0; i < finalItems.count; i++) {
        UITabBarItem *item = finalItems[i];
        WriteLog(@"  final[%ld] %@", (long)i, item.title ?: @"(无)");
    }
    WriteLog(@"Filter completed");
}

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    filterTabBarController(self);
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear");
    // 再次确保过滤
    filterTabBarController(self);
}

// 拦截 setSelectedIndex
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"setSelectedIndex called with %ld", (long)selectedIndex);
    
    // 使用 KVC 获取 viewControllers
    NSArray *vcs = [self valueForKey:@"viewControllers"];
    if (vcs.count == 2) {
        if (selectedIndex >= vcs.count) {
            selectedIndex = 0;
            WriteLog(@"Index out of bounds, redirected to 0");
        }
        UIViewController *targetVC = vcs[selectedIndex];
        NSString *title = targetVC.tabBarItem.title;
        if (![title isEqualToString:@"首页"] && ![title isEqualToString:@"我的"]) {
            // 重定向到"我的"
            for (NSInteger i = 0; i < vcs.count; i++) {
                if ([vcs[i].tabBarItem.title isEqualToString:@"我的"]) {
                    selectedIndex = i;
                    WriteLog(@"Redirected to '我的' index: %ld", (long)i);
                    break;
                }
            }
        }
    }
    %orig(selectedIndex);
    WriteLog(@"setSelectedIndex final: %ld", (long)selectedIndex);
}

%end

// =============================================================
// Hook UITabBar：拦截 setItems 防止重置
// =============================================================
%hook UITabBar

- (void)setItems:(NSArray<UITabBarItem *> *)items animated:(BOOL)animated {
    WriteLog(@"UITabBar setItems called with %lu items", (unsigned long)items.count);
    // 如果 items 数量为 5，尝试过滤
    if (items.count == 5) {
        NSArray *filtered = filterTabBarItems(items);
        if (filtered.count == 2) {
            WriteLog(@"Filtering 5 items to 2 items");
            %orig(filtered, animated);
            return;
        }
    }
    %orig(items, animated);
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
