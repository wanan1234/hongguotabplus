#import <UIKit/UIKit.h>
#import <substrate.h>

// 红果短剧的 Bundle ID
#define BUNDLE_ID @"com.phoenix.video"

// 使用 NSClassFromString 动态获取类，避免硬编码
static Class SSTabBarControllerClass;
static Class SSVideoSeriesFeedViewControllerClass;

%ctor {
    // 在加载时获取类
    SSTabBarControllerClass = NSClassFromString(@"SSTabBarController");
    SSVideoSeriesFeedViewControllerClass = NSClassFromString(@"SSVideoSeriesFeedViewController");
    
    if (SSTabBarControllerClass) {
        %init(SSTabBarControllerClass);
    }
    if (SSVideoSeriesFeedViewControllerClass) {
        %init(SSVideoSeriesFeedViewControllerClass);
    }
}

%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    // 读取用户设置（默认开启）
    BOOL hidden = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    if (hidden) {
        self.tabBar.hidden = YES;
        // 也可将 tabBar 移出屏幕
        // self.tabBar.frame = CGRectMake(0, self.view.bounds.size.height, 0, 0);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    // 确保每次出现时都隐藏
    BOOL hidden = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];
    if (hidden) {
        self.tabBar.hidden = YES;
    }
}

%end

%hook SSVideoSeriesFeedViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (fullscreen) {
        // 使父控制器（SSTabBarController）的视图全屏
        UIViewController *parent = self.parentViewController;
        if ([parent isKindOfClass:SSTabBarControllerClass]) {
            parent.view.frame = [UIScreen mainScreen].bounds;
        }
        // 自身视图也全屏
        self.view.frame = [UIScreen mainScreen].bounds;
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    if (fullscreen) {
        self.view.frame = [UIScreen mainScreen].bounds;
    }
}

%end
