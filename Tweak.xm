// =============================================================
//  HongGuoFullScreen — 精简 TabBar（拦截重定向）
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

// 查找“我的”控制器索引
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

// 过滤函数
static void filterTabBar(UITabBarController *tab) {
    if (!tab) return;
    if (gFiltered) {
        WriteLog(@"Already filtered, skip");
        return;
    }
    
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
    
    // 只在首次设置 selectedIndex
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
    // 强制转换为 UITabBarController
    filterTabBar((UITabBarController *)self);
}

// 拦截 setSelectedIndex
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"setSelectedIndex called: %ld", (long)selectedIndex);
    
    UITabBarController *tab = (UITabBarController *)self;
    NSArray *vcs = tab.viewControllers;
    
    // 如果已经过滤，且选中索引在范围内
    if (gFiltered && selectedIndex < vcs.count) {
        UIViewController *targetVC = vcs[selectedIndex];
        NSString *title = targetVC.tabBarItem.title;
        WriteLog(@"Target VC title: %@", title ?: @"(无)");
        
        // 如果选中的是“剧场”（索引1），重定向到“我的”
        if ([title isEqualToString:@"剧场"]) {
            NSInteger myIndex = indexOfMyVC(vcs);
            if (myIndex != -1) {
                WriteLog(@"Redirect '剧场' to '我的' (index %ld)", (long)myIndex);
                %orig(myIndex);
                return;
            } else {
                WriteLog(@"My VC not found, redirect to 0");
                %orig(0);
                return;
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
    WriteLog(@"HongGuoFullScreen 加载（最终版）");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
}
