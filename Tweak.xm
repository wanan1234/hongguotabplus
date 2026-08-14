// =============================================================
//  HongGuoFullScreen — 精简 TabBar（参考番茄小说实现）
//  只保留首页和我的，拦截 setSelectedIndex 解决跳转错乱
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

// =============================================================
// 辅助函数
// =============================================================

// 获取“我的”控制器的索引
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

// 过滤 ViewControllers
static NSArray *filterViewControllers(NSArray *vcs) {
    if (vcs.count == 0) return vcs;
    NSMutableArray *result = [NSMutableArray array];
    for (UIViewController *vc in vcs) {
        NSString *title = vc.tabBarItem.title;
        if ([title isEqualToString:@"首页"] || [title isEqualToString:@"我的"]) {
            [result addObject:vc];
        }
    }
    return result;
}

// 过滤 TabBarItems
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

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    
    // 过滤 viewControllers
    NSArray *originalVCs = self.viewControllers;
    if (originalVCs.count >= 5) {
        NSArray *filteredVCs = filterViewControllers(originalVCs);
        if (filteredVCs.count == 2) {
            [self setViewControllers:filteredVCs animated:NO];
            WriteLog(@"viewControllers filtered: %@, %@", 
                [filteredVCs[0] tabBarItem].title,
                [filteredVCs[1] tabBarItem].title);
        }
    }
    
    // 过滤 tabBar.items
    NSArray *originalItems = self.tabBar.items;
    if (originalItems.count >= 5) {
        NSArray *filteredItems = filterTabBarItems(originalItems);
        if (filteredItems.count == 2) {
            [self.tabBar setItems:filteredItems animated:NO];
            WriteLog(@"tabBar.items filtered: %@, %@",
                [filteredItems[0] title],
                [filteredItems[1] title]);
        }
    }
    
    [self.tabBar setNeedsLayout];
    [self.tabBar layoutIfNeeded];
    self.selectedIndex = 0;
    WriteLog(@"TabBar filter completed");
}

// =============================================================
// 拦截 setSelectedIndex（参考番茄小说）
// =============================================================
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"setSelectedIndex called: %ld", (long)selectedIndex);
    
    // 获取当前 viewControllers
    NSArray *vcs = self.viewControllers;
    WriteLog(@"current viewControllers count: %lu", (unsigned long)vcs.count);
    
    // 如果 viewControllers 只有 2 个（首页和我的）
    if (vcs.count == 2) {
        // 越界修正
        if (selectedIndex >= vcs.count) {
            selectedIndex = 0;
            WriteLog(@"Index out of bounds, redirected to 0");
        }
        
        // 如果试图选中“剧场”（原本索引1），重定向到“我的”
        if (selectedIndex < vcs.count) {
            UIViewController *targetVC = vcs[selectedIndex];
            NSString *title = targetVC.tabBarItem.title;
            WriteLog(@"Target VC title: %@", title ?: @"(无)");
            
            if ([title isEqualToString:@"剧场"] || [title isEqualToString:@"商城"] || [title isEqualToString:@"福利"]) {
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

// =============================================================
// Hook UITabBar：拦截 setItems 防止重置
// =============================================================
%hook UITabBar

- (void)setItems:(NSArray<UITabBarItem *> *)items animated:(BOOL)animated {
    WriteLog(@"UITabBar setItems called with %lu items", (unsigned long)items.count);
    // 如果 items 数量不是 2，可能是系统在尝试重置，但我们的 viewControllers 已经是 2 个了，所以允许
    // 但为了安全，如果是重置为 5 个，我们过滤掉
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
