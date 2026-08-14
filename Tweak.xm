// =============================================================
//  HongGuoFullScreen — 隐藏多余 TabBar 按钮
//  通过遍历 tabBar 子视图隐藏多余按钮，保留首页和我的
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

static void hideExtraTabBarButtons(id tabController) {
    if (!tabController) return;
    if (![tabController isKindOfClass:[UITabBarController class]]) return;
    UITabBarController *tab = (UITabBarController *)tabController;
    
    UITabBar *tabBar = tab.tabBar;
    if (!tabBar) return;
    
    // 遍历 tabBar 的子视图，找到 UITabBarButton
    NSMutableArray *buttons = [NSMutableArray array];
    for (UIView *subview in tabBar.subviews) {
        if ([NSStringFromClass([subview class]) isEqualToString:@"UITabBarButton"]) {
            [buttons addObject:subview];
        }
    }
    
    WriteLog(@"Found %lu UITabBarButton(s)", (unsigned long)buttons.count);
    
    // 假设索引 0 是首页，索引 4 是我的，其他隐藏
    for (NSInteger i = 0; i < buttons.count; i++) {
        UIView *button = buttons[i];
        BOOL shouldHide = (i != 0 && i != 4);
        if (shouldHide) {
            button.hidden = YES;
            button.alpha = 0.0;
            button.userInteractionEnabled = NO;
            WriteLog(@"Hiding button at index %ld", (long)i);
        } else {
            // 保留首页和我的
            button.hidden = NO;
            button.alpha = 1.0;
            button.userInteractionEnabled = YES;
            WriteLog(@"Keeping button at index %ld", (long)i);
        }
    }
    
    // 强制刷新布局让剩下的按钮自适应
    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];
}

%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    // 延迟执行确保 tabBar 已创建
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        hideExtraTabBarButtons(self);
    });
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    hideExtraTabBarButtons(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    hideExtraTabBarButtons(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    static NSTimeInterval last = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - last > 0.2) {
        last = now;
        hideExtraTabBarButtons(self);
    }
}

%end

%ctor {
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
}
