// =============================================================
//  HongGuoFullScreen — 精简 TabBar（参考番茄小说方案）
//  只保留首页和我的，拦截 setSelectedIndex 修正跳转错乱
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

// ---------- 辅助函数 ----------
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
        WriteLog(@"  [%ld] %@", (long)i, [vcs[i] tabBarItem].title ?: @"(无)");
    }
    
    // 1. 过滤 viewControllers（只保留索引0和4）
    NSArray *filteredVCs = @[vcs[0], vcs[4]];
    [tab setViewControllers:filteredVCs animated:NO];
    WriteLog(@"viewControllers filtered to %lu items", (unsigned long)filteredVCs.count);
    
    // 2. 过滤 tabBar.items
    NSArray *items = tab.tabBar.items;
    if (items.count >= 5) {
        NSArray *filteredItems = @[items[0], items[4]];
        [tab.tabBar setItems:filteredItems animated:NO];
        WriteLog(@"tabBar.items filtered");
    }
    
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    
    // 只在首次设置 selectedIndex（不强制跳转）
    tab.selectedIndex = 0;
    
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

// =============================================================
// 拦截 setSelectedIndex（只修正无效请求，参考番茄小说）
// =============================================================
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"setSelectedIndex called: %ld", (long)selectedIndex);
    
    if (gFiltered) {
        NSArray *vcs = self.viewControllers;
        WriteLog(@"current viewControllers count: %lu", (unsigned long)vcs.count);
        
        // 1. 越界修正
        if (selectedIndex >= vcs.count) {
            selectedIndex = 0;
            WriteLog(@"Index out of bounds, redirected to 0");
        }
        
        // 2. 如果试图选中无效页面（剧场、商城、福利），重定向到“我的”或“首页”
        if (selectedIndex < vcs.count) {
            UIViewController *targetVC = vcs[selectedIndex];
            NSString *title = targetVC.tabBarItem.title;
            WriteLog(@"Target VC title: %@", title ?: @"(无)");
            
            // 如果选中了“剧场”“商城”“福利”，重定向到“我的”
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

// =============================================================
// 构造函数
// =============================================================
%ctor {
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
}
