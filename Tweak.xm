#import <UIKit/UIKit.h>
#import <substrate.h>

// 日志工具 (简化)
static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject] ?: @"/var/mobile/Documents";
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"HongGuo.log"];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [df stringFromDate:[NSDate date]], msg];
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

// =============================================
// 辅助类
// =============================================
@interface HongGuoHelper : NSObject
+ (void)showSettingsMenuFromWindow:(UIWindow *)window;
+ (void)applySettings;
+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window;
@end

@implementation HongGuoHelper

+ (void)showSettingsMenuFromWindow:(UIWindow *)window {
    WriteLog(@"showSettingsMenuFromWindow");
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;

    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果设置"
                                                                   message:[NSString stringWithFormat:@"底栏：%@", hideTab ? @"已精简" : @"默认"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 精简底栏", hideTab ? @"恢复" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                [HongGuoHelper applySettings];
                                                [HongGuoHelper showToast:[NSString stringWithFormat:@"底栏已%@", newVal ? @"精简" : @"恢复"] fromWindow:window];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                NSString *logPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"HongGuo.log"];
                                                NSString *logContent = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
                                                if (!logContent) logContent = @"日志文件不存在或为空";
                                                UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"日志内容" message:logContent preferredStyle:UIAlertControllerStyleAlert];
                                                [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
                                                [topVC presentViewController:logAlert animated:YES completion:nil];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [topVC presentViewController:alert animated:YES completion:nil];
}

// 核心：遍历所有窗口，找到 UITabBar，精简按钮
+ (void)applySettings {
    WriteLog(@"applySettings");
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    if (!hide) {
        WriteLog(@"精简模式未开启，跳过");
        // 如果要恢复，我们可以尝试重新加载（但无法恢复原始，提示重启）
        return;
    }

    // 遍历所有窗口
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        [self processView:window];
    }
}

+ (void)processView:(UIView *)view {
    // 找到 UITabBar
    if ([view isKindOfClass:[UITabBar class]]) {
        WriteLog(@"找到 UITabBar: %@", view);
        [self simplifyTabBar:(UITabBar *)view];
        return;
    }
    for (UIView *sub in view.subviews) {
        [self processView:sub];
    }
}

+ (void)simplifyTabBar:(UITabBar *)tabBar {
    // 获取所有按钮
    NSArray *buttons = tabBar.subviews;
    NSMutableArray *keepButtons = [NSMutableArray array];
    NSArray *keepTitles = @[@"首页", @"我的"]; // 要保留的按钮标题

    for (UIView *button in buttons) {
        // 检查是否是 UITabBarButton（私有类）
        if ([NSStringFromClass([button class]) rangeOfString:@"TabBarButton"].location != NSNotFound) {
            // 尝试获取按钮的标题
            NSString *title = nil;
            // 遍历子视图查找 UILabel
            for (UIView *sub in button.subviews) {
                if ([sub isKindOfClass:[UILabel class]]) {
                    title = [(UILabel *)sub text];
                    break;
                }
            }
            // 如果没找到，尝试用 accessibilityLabel
            if (!title) {
                title = button.accessibilityLabel;
            }
            WriteLog(@"按钮标题: %@", title);
            // 判断是否保留
            BOOL keep = NO;
            for (NSString *keepTitle in keepTitles) {
                if ([title isEqualToString:keepTitle]) {
                    keep = YES;
                    break;
                }
            }
            if (keep) {
                [keepButtons addObject:button];
            } else {
                // 隐藏并禁用交互
                button.hidden = YES;
                button.userInteractionEnabled = NO;
                WriteLog(@"隐藏按钮: %@", title);
            }
        }
    }

    // 重新布局：让保留的按钮均匀分布（简单做法：设置按钮 frame）
    // 由于 UITabBar 的按钮布局由系统管理，我们无法直接设置 frame，
    // 但我们可以利用 KVC 或直接修改 tabBar 的 items 数组。
    // 更可靠的方法是修改 tabBar 的 items 属性（但需确保控制器也对应）
    // 由于我们只是隐藏了按钮，点击事件已被禁用，但视觉上可能留下空隙。
    // 更好的办法是重新设置 tabBar.items，只保留需要的项目（但需要知道对应的 UITabBarItem）。
    // 这里我们暂且只隐藏，不调整布局，后续可以优化。
    WriteLog(@"精简完成，保留了 %lu 个按钮", (unsigned long)keepButtons.count);
}

+ (void)showToast:(NSString *)msg fromWindow:(UIWindow *)window {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

@end

// =============================================
// Hook UIWindow：三指长按
// =============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleLongPress:)];
        gesture.numberOfTouchesRequired = 3;
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
        WriteLog(@"UIWindow initialized");
    }
    return self;
}

%new
- (void)hongguo_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    WriteLog(@"3-finger long press");
    [HongGuoHelper showSettingsMenuFromWindow:self];
}

%end

// =============================================
// Hook 视图出现时应用设置
// =============================================
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [HongGuoHelper applySettings];
        });
    });
}

- (void)viewWillLayoutSubviews {
    %orig;
    // 每次布局时重新应用，但限制频率
    static NSTimeInterval last = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - last > 0.5) {
        last = now;
        [HongGuoHelper applySettings];
    }
}

%end

// =============================================
// 构造函数
// =============================================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        WriteLog(@"HongGuoFullScreen loaded");
        [HongGuoHelper applySettings];
    });
}
