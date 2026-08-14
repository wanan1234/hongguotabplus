// =============================================================
//  HongGuoFullScreen — 精简 TabBar（最终稳定版）
//  只过滤 SSTabBar 的 items，不干扰 viewControllers
//  包含双指双击弹窗开关 + 重启功能
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>

static BOOL HGIsEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreenEnabled"];
}

// =============================================================
// Hook SSTabBar（红果自定义 TabBar）
// =============================================================
%hook SSTabBar

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    if (HGIsEnabled() && items.count > 2) {
        // 只保留首页（索引0）和我的（索引4）
        NSArray *filtered = @[items[0], items[4]];
        %orig(filtered, animated);
        return;
    }
    %orig(items, animated);
}

%end

// =============================================================
// 双指双击手势弹出菜单
// =============================================================
static void showSettingsMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    BOOL enabled = HGIsEnabled();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果Tab精简控制"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@", enabled ? @"已开启" : @"已关闭"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:enabled ? @"关闭精简" : @"开启精简" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        BOOL newState = !enabled;
        [[NSUserDefaults standardUserDefaults] setBool:newState forKey:@"HongGuoFullScreenEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        UIAlertController *restartAlert = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                               message:@"切换后需要重启才能生效，是否立即重启？"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
        [restartAlert addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        [restartAlert addAction:[UIAlertAction actionWithTitle:@"稍后手动重启" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:restartAlert animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }
    
    [topVC presentViewController:alert animated:YES completion:nil];
}

// =============================================================
// Hook UIWindow 添加双指双击手势
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
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        showSettingsMenu(self);
    }
}

%end

// =============================================================
// 构造函数
// =============================================================
%ctor {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"HongGuoFullScreenEnabled"]) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HongGuoFullScreenEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    NSLog(@"[HongGuo] TabBar精简插件加载成功，开关状态：%@", HGIsEnabled() ? @"开启" : @"关闭");
}
