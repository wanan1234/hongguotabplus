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

// 这里直接用 `id` 和 KVC 获取 viewControllers，避免编译问题
static void fixTabBar(id tabController) {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) return;
    UITabBarController *tab = (UITabBarController *)tabController;

    // 确保已经过滤过
    NSArray *vcs = tab.viewControllers;
    if (vcs.count != 2) {
        WriteLog(@"Expected 2 viewControllers, but got %lu, skip", (unsigned long)vcs.count);
        return;
    }

    // 检查 title
    NSString *title0 = [vcs[0] tabBarItem].title;
    NSString *title1 = [vcs[1] tabBarItem].title;
    WriteLog(@"Current titles: [0]=%@, [1]=%@", title0, title1);

    // 确保索引 1 是“我的”，如果不是，说明过滤失败了，重新过滤
    if (![title1 isEqualToString:@"我的"]) {
        WriteLog(@"Index 1 is not '我的', re-filtering...");
        // 根据标题重新排序
        NSMutableArray *sorted = [NSMutableArray array];
        for (UIViewController *vc in vcs) {
            if ([vc.tabBarItem.title isEqualToString:@"首页"]) {
                [sorted insertObject:vc atIndex:0];
            } else if ([vc.tabBarItem.title isEqualToString:@"我的"]) {
                [sorted addObject:vc];
            }
        }
        if (sorted.count == 2) {
            [tab setViewControllers:sorted animated:NO];
            WriteLog(@"Re-filtered to: %@, %@", [sorted[0] tabBarItem].title, [sorted[1] tabBarItem].title);
            tab.selectedIndex = 0;
            [tab.tabBar setItems:@[[sorted[0] tabBarItem], [sorted[1] tabBarItem]] animated:NO];
        }
    }
}

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    // 先过滤
    NSArray *vcs = self.viewControllers;
    if (vcs.count >= 5) {
        NSArray *filtered = @[vcs[0], vcs[4]];
        [self setViewControllers:filtered animated:NO];
        [self.tabBar setItems:@[filtered[0].tabBarItem, filtered[1].tabBarItem] animated:NO];
        self.selectedIndex = 0;
        WriteLog(@"Filtered to: %@, %@", filtered[0].tabBarItem.title, filtered[1].tabBarItem.title);
    }
}

// =============================================================
// 拦截 setSelectedIndex：直接修正
// =============================================================
- (void)setSelectedIndex:(NSInteger)selectedIndex {
    WriteLog(@"setSelectedIndex called with: %ld", (long)selectedIndex);
    
    // 如果已经过滤，检查目标
    NSArray *vcs = self.viewControllers;
    if (vcs.count == 2) {
        // 检查是否有无效索引
        if (selectedIndex >= vcs.count) {
            selectedIndex = 0;
            WriteLog(@"Index out of bounds, set to 0");
        } else {
            UIViewController *target = vcs[selectedIndex];
            NSString *title = target.tabBarItem.title;
            WriteLog(@"Target title: %@", title);
            // 如果目标是“剧场”“商城”“福利”，则重定向到“我的”
            if ([title isEqualToString:@"剧场"] || [title isEqualToString:@"商城"] || [title isEqualToString:@"福利"]) {
                // 查找“我的”索引
                NSInteger myIndex = -1;
                for (NSInteger i = 0; i < vcs.count; i++) {
                    if ([vcs[i].tabBarItem.title isEqualToString:@"我的"]) {
                        myIndex = i;
                        break;
                    }
                }
                if (myIndex != -1) {
                    selectedIndex = myIndex;
                    WriteLog(@"Redirect to '我的' index: %ld", (long)myIndex);
                } else {
                    selectedIndex = 0;
                    WriteLog(@"Cannot find '我的', set to 0");
                }
            }
        }
    } else {
        // 如果还没过滤，尝试过滤
        if (vcs.count >= 5) {
            NSArray *filtered = @[vcs[0], vcs[4]];
            [self setViewControllers:filtered animated:NO];
            [self.tabBar setItems:@[filtered[0].tabBarItem, filtered[1].tabBarItem] animated:NO];
            self.selectedIndex = 0;
            WriteLog(@"Filtered in setSelectedIndex");
            // 然后递归调用一次，但用新索引
            [self setSelectedIndex:0];
            return;
        }
    }
    
    %orig(selectedIndex);
    WriteLog(@"setSelectedIndex completed: %ld", (long)selectedIndex);
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
