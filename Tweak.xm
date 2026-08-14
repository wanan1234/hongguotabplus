// =============================================================
//  HongGuoFullScreen — 精简红果Tab栏（只保留首页+我的）
//  双指双击弹出菜单，自适应布局
//  完整诊断日志
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <objc/runtime.h>

// 声明 SSTabBarController 为 UITabBarController 的子类，让编译器识别其属性和方法
@interface SSTabBarController : UITabBarController
@end

// 日志工具
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

// 核心：过滤 TabBar 控制器，只保留首页(索引0)和我的(索引4)
static void filterTabBarController(UITabBarController *tabController) {
    if (!tabController) return;
    WriteLog(@"filterTabBarController 被调用，当前 viewControllers 数量: %lu", (unsigned long)tabController.viewControllers.count);
    
    NSArray *originalVCs = tabController.viewControllers;
    if (originalVCs.count >= 5) {
        NSMutableArray *filtered = [NSMutableArray array];
        [filtered addObject:originalVCs[0]]; // 首页
        [filtered addObject:originalVCs[4]]; // 我的
        
        WriteLog(@"过滤前: %@", [originalVCs valueForKey:@"title"]);
        WriteLog(@"过滤后: %@", [filtered valueForKey:@"title"]);
        
        [tabController setViewControllers:filtered animated:NO];
        [tabController.tabBar setNeedsLayout];
        [tabController.tabBar layoutIfNeeded];
        tabController.selectedIndex = 0;
        WriteLog(@"TabBar 已精简，选中索引: %ld", (long)tabController.selectedIndex);
    } else {
        WriteLog(@"viewControllers 数量不足5个，当前数量: %lu", (unsigned long)originalVCs.count);
    }
}

// =============================================================
// 手势控制（双指双击）
// =============================================================
static void showToast(NSString *msg, UIWindow *window) {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

static void showSettingsMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果Tab控制"
                                                                   message:@"日志路径: Documents/HongGuo.log\n点击查看日志或切换开关"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths firstObject];
        NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"HongGuo.log"];
        NSString *logContent = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        if (!logContent) logContent = @"日志文件不存在或为空";
        UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"日志内容" message:logContent preferredStyle:UIAlertControllerStyleAlert];
        [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:logAlert animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }
    [topVC presentViewController:alert animated:YES completion:nil];
}

// =============================================================
// Hook UIWindow：双指双击
// =============================================================
%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UITapGestureRecognizer *gesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hg_handleDoubleTap:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.numberOfTapsRequired = 2;
        [self addGestureRecognizer:gesture];
        WriteLog(@"双指双击手势已添加到窗口");
    }
    return self;
}
%new
- (void)hg_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        if (@available(iOS 10.0, *)) {
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
        }
        WriteLog(@"用户触发双指双击，弹出菜单");
        showSettingsMenu(self);
    }
}
%end

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewWillAppear");
    filterTabBarController(self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    WriteLog(@"SSTabBarController viewDidAppear");
    filterTabBarController(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    WriteLog(@"SSTabBarController viewDidLayoutSubviews");
    filterTabBarController(self);
}

- (void)setViewControllers:(NSArray<UIViewController *> *)viewControllers animated:(BOOL)animated {
    WriteLog(@"SSTabBarController setViewControllers 被调用，数量: %lu", (unsigned long)viewControllers.count);
    %orig;
    // 再次过滤以确保
    filterTabBarController(self);
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
    // 延迟执行，确保窗口已创建
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].windows.firstObject;
        if (keyWindow) {
            // 查找 SSTabBarController
            UIViewController *root = keyWindow.rootViewController;
            if ([root isKindOfClass:[UITabBarController class]]) {
                WriteLog(@"根控制器是 UITabBarController，直接过滤");
                filterTabBarController((UITabBarController *)root);
            } else {
                // 遍历子控制器
                for (UIViewController *child in root.childViewControllers) {
                    if ([child isKindOfClass:[UITabBarController class]]) {
                        WriteLog(@"找到子控制器 UITabBarController");
                        filterTabBarController((UITabBarController *)child);
                        break;
                    }
                }
            }
        }
    });
}
