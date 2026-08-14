// =============================================================
//  HongGuoFullScreen — 精简 TabBar（基于 KVC，保证编译通过）
//  参考番茄小说插件实现，双指双击菜单
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

// ---------- 全局状态 ----------
static BOOL gFiltered = NO;

// ---------- 辅助函数 ----------
static NSArray *filterViewControllers(NSArray *vcs) {
    if (vcs.count == 0) return vcs;
    NSMutableArray *result = [NSMutableArray array];
    for (id vc in vcs) {
        id item = [vc valueForKey:@"tabBarItem"];
        NSString *title = [item valueForKey:@"title"];
        if ([title isEqualToString:@"首页"] || [title isEqualToString:@"我的"]) {
            [result addObject:vc];
        }
    }
    return result;
}

static NSArray *filterTabBarItems(NSArray *items) {
    if (items.count == 0) return items;
    NSMutableArray *result = [NSMutableArray array];
    for (id item in items) {
        NSString *title = [item valueForKey:@"title"];
        if ([title isEqualToString:@"首页"] || [title isEqualToString:@"我的"]) {
            [result addObject:item];
        }
    }
    return result;
}

static NSInteger indexOfMyVC(NSArray *vcs) {
    for (NSInteger i = 0; i < vcs.count; i++) {
        id vc = vcs[i];
        id item = [vc valueForKey:@"tabBarItem"];
        NSString *title = [item valueForKey:@"title"];
        if ([title isEqualToString:@"我的"]) {
            return i;
        }
    }
    return -1;
}

static void filterTabBarController(id tabController) {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) {
        WriteLog(@"Not a UITabBarController");
        return;
    }
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
    WriteLog(@"Filtering...");
    
    // 1. 过滤 viewControllers
    NSArray *filteredVCs = filterViewControllers(vcs);
    if (filteredVCs.count == 2) {
        [tab setViewControllers:filteredVCs animated:NO];
        WriteLog(@"viewControllers filtered to: %@, %@", 
            [[filteredVCs[0] valueForKey:@"tabBarItem"] valueForKey:@"title"],
            [[filteredVCs[1] valueForKey:@"tabBarItem"] valueForKey:@"title"]);
    }
    
    // 2. 过滤 tabBar.items
    NSArray *items = tab.tabBar.items;
    if (items.count >= 5) {
        NSArray *filteredItems = filterTabBarItems(items);
        if (filteredItems.count == 2) {
            [tab.tabBar setItems:filteredItems animated:NO];
            WriteLog(@"tabBar.items filtered to: %@, %@",
                [filteredItems[0] valueForKey:@"title"],
                [filteredItems[1] valueForKey:@"title"]);
        }
    }
    
    [tab.tabBar setNeedsLayout];
    [tab.tabBar layoutIfNeeded];
    tab.selectedIndex = 0;
    gFiltered = YES;
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
    if (!gFiltered) {
        filterTabBarController(self);
    }
}

// 拦截 setSelectedIndex
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"setSelectedIndex called: %ld", (long)selectedIndex);
    
    // 使用 KVC 获取 viewControllers
    NSArray *vcs = [self valueForKey:@"viewControllers"];
    if (vcs.count == 2) {
        // 越界修正
        if (selectedIndex >= vcs.count) {
            selectedIndex = 0;
            WriteLog(@"Index out of bounds, redirected to 0");
        }
        // 检查目标标题
        if (selectedIndex < vcs.count) {
            id vc = vcs[selectedIndex];
            id item = [vc valueForKey:@"tabBarItem"];
            NSString *title = [item valueForKey:@"title"];
            WriteLog(@"Target VC title: %@", title ?: @"(无)");
            
            if (![title isEqualToString:@"首页"] && ![title isEqualToString:@"我的"]) {
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
// Hook UITabBar：拦截 setItems，防止重置
// =============================================================
%hook UITabBar

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    WriteLog(@"UITabBar setItems called with %lu items", (unsigned long)items.count);
    if (gFiltered && items.count == 5) {
        NSArray *filtered = filterTabBarItems(items);
        if (filtered.count == 2) {
            WriteLog(@"Filtering 5 items to 2");
            %orig(filtered, animated);
            return;
        }
    }
    %orig(items, animated);
}

%end

// =============================================================
// Hook UIWindow：双指双击菜单
// =============================================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hg_handleDoubleTap:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.numberOfTapsRequired = 2;
        [self addGestureRecognizer:gesture];
    }
    return self;
}

%new
- (void)hg_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    UIViewController *topVC = self.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    
    BOOL enabled = gFiltered;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果精简Tab"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@\n日志: Documents/HongGuo.log", enabled ? @"已精简" : @"未精简"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *logPath = [paths.firstObject stringByAppendingPathComponent:@"HongGuo.log"];
        NSString *content = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil] ?: @"日志为空";
        UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"日志内容" message:content preferredStyle:UIAlertControllerStyleAlert];
        [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
        [topVC presentViewController:logAlert animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 0, 0);
    }
    [topVC presentViewController:alert animated:YES completion:nil];
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
