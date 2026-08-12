#import <UIKit/UIKit.h>
#import <substrate.h>

// 红果短剧 Bundle ID
#define BUNDLE_ID @"com.phoenix.video"

// 辅助函数：获取当前顶层控制器
static UIViewController *topViewController(UIViewController *root) {
    if (!root) return nil;
    while (root.presentedViewController) {
        root = root.presentedViewController;
    }
    if ([root isKindOfClass:[UINavigationController class]]) {
        return [(UINavigationController *)root topViewController];
    }
    return root;
}

// 动态获取红果的类（兼容版本更新）
static Class SSTabBarControllerClass;
static Class SSVideoSeriesFeedViewControllerClass;

%ctor {
    // 获取类
    SSTabBarControllerClass = NSClassFromString(@"SSTabBarController");
    SSVideoSeriesFeedViewControllerClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
    
    if (SSTabBarControllerClass) {
        %init(SSTabBarControllerClass);
    }
    if (SSVideoSeriesFeedViewControllerClass) {
        %init(SSVideoSeriesFeedViewControllerClass);
    }
}

// ============================================
// 1. 双指长按手势（在 UIWindow 上）
// ============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        // 添加双指长按手势
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleDoubleLongPress:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.minimumPressDuration = 0.8; // 0.8秒
        [self addGestureRecognizer:gesture];
    }
    return self;
}

%new
- (void)hongguo_handleDoubleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    // 获取当前顶层控制器
    UIViewController *topVC = topViewController(self.rootViewController);
    if (!topVC) return;
    
    // 读取当前设置状态
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    BOOL hideTabBar = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    
    // 构造 ActionSheet
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果全屏设置"
                                                                   message:[NSString stringWithFormat:@"全屏模式: %@\n隐藏底栏: %@", fullscreen ? @"开启" : @"关闭", hideTabBar ? @"开启" : @"关闭"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 切换全屏
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 全屏模式", fullscreen ? @"关闭" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newValue = !fullscreen;
                                                [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@"HongGuoFullScreen"];
                                                // 刷新界面（可发通知或直接重新加载）
                                                // 这里简单提示
                                                [self hongguo_showToast:[NSString stringWithFormat:@"全屏模式已%@", newValue ? @"开启" : @"关闭"]];
                                            }]];
    
    // 切换隐藏底栏
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 隐藏底栏", hideTabBar ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newValue = !hideTabBar;
                                                [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:@"HongGuoHideTabBar"];
                                                // 立即应用（刷新 tabBar）
                                                [self hongguo_applyTabBarVisibility];
                                                [self hongguo_showToast:[NSString stringWithFormat:@"底栏已%@", newValue ? @"隐藏" : @"显示"]];
                                            }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // iPad 适配
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 0, 0);
    }
    
    [topVC presentViewController:alert animated:YES completion:nil];
}

// 辅助方法：应用底栏隐藏设置
%new
- (void)hongguo_applyTabBarVisibility {
    UIViewController *root = self.rootViewController;
    if ([root isKindOfClass:SSTabBarControllerClass]) {
        UITabBarController *tabBarController = (UITabBarController *)root;
        BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
        tabBarController.tabBar.hidden = hide;
        // 也可调整 frame 避免空白
        if (hide) {
            tabBarController.tabBar.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.height, 0, 0);
        } else {
            // 恢复默认位置（需要计算，这里简化）
            tabBarController.tabBar.frame = CGRectMake(0, [UIScreen mainScreen].bounds.size.height - 83, [UIScreen mainScreen].bounds.size.width, 83);
        }
    }
}

// 简单 Toast 提示（用 UIAlertController 或系统 Toast）
%new
- (void)hongguo_showToast:(NSString *)message {
    UIViewController *topVC = topViewController(self.rootViewController);
    if (!topVC) return;
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [topVC presentViewController:toast animated:YES completion:nil];
    // 自动消失
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

%end

// ============================================
// 2. Hook TabBarController：应用隐藏设置
// ============================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    self.tabBar.hidden = hide;
    if (hide) {
        // 移出屏幕
        self.tabBar.frame = CGRectMake(0, self.view.bounds.size.height, 0, 0);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    self.tabBar.hidden = hide;
    if (hide) {
        self.tabBar.frame = CGRectMake(0, self.view.bounds.size.height, 0, 0);
    }
}

%end

// ============================================
// 3. Hook 首页控制器：全屏
// ============================================
%hook SSVideoSeriesFeedViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (fullscreen) {
        // 父控制器全屏
        UIViewController *parent = self.parentViewController;
        if ([parent isKindOfClass:SSTabBarControllerClass]) {
            parent.view.frame = [UIScreen mainScreen].bounds;
        }
        // 自身全屏
        self.view.frame = [UIScreen mainScreen].bounds;
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (fullscreen) {
        self.view.frame = [UIScreen mainScreen].bounds;
        // 确保父视图也全屏
        UIViewController *parent = self.parentViewController;
        if ([parent isKindOfClass:SSTabBarControllerClass]) {
            parent.view.frame = [UIScreen mainScreen].bounds;
        }
    }
}

%end
