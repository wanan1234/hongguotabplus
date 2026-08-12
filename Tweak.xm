#import <UIKit/UIKit.h>
#import <substrate.h>

static BOOL HGShouldApply() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.phoenix.video"];
}

// 递归透明化底栏和特定视图
static void HGTransparentizeViews(UIView *view) {
    if (!view) return;
    @try {
        // 1. 透明化 UITabBar（红果的底栏）
        if ([view isKindOfClass:[UITabBar class]]) {
            [UIView performWithoutAnimation:^{
                view.alpha = 0.0;
                view.userInteractionEnabled = NO;
                for (UIView *sub in view.subviews) {
                    sub.alpha = 0.0;
                    sub.userInteractionEnabled = NO;
                }
            }];
            return;
        }
        
        // 2. 如果是首页视图（SSVideoSeriesFeedViewController 的 view），调整全屏
        // 由于不知道具体类，我们可以通过父控制器判断，但这里简单处理：
        // 如果是 UIViewController 的 view，并且其父控制器是 UITabBarController，则全屏
        UIViewController *vc = [self hg_viewControllerForView:view];
        if (vc && [vc.parentViewController isKindOfClass:[UITabBarController class]]) {
            // 如果该视图是控制器的主视图，并且是 UITabBarController 的子控制器，则全屏
            if (vc.view == view) {
                BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
                if (fullscreen) {
                    [UIView performWithoutAnimation:^{
                        view.frame = [UIScreen mainScreen].bounds;
                    }];
                }
            }
        }
        
        // 递归子视图
        for (UIView *sub in view.subviews) {
            HGTransparentizeViews(sub);
        }
    } @catch (NSException *e) {}
}

// 辅助：获取 view 所在的 ViewController
+ (UIViewController *)hg_viewControllerForView:(UIView *)view {
    UIResponder *responder = view;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
    }
    return nil;
}

static void HGProcessAllWindows() {
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        HGTransparentizeViews(window);
    }
}

static void HGStartTimer() {
    // 立即执行一次
    HGProcessAllWindows();
    // 每隔 0.1 秒执行一次，共 15 次（持续 1.5 秒），确保覆盖加载完成
    for (int i = 1; i <= 15; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            HGProcessAllWindows();
        });
    }
}

// Hook UIViewController 的 viewDidAppear 来触发透明化
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (HGShouldApply()) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                HGStartTimer();
            });
        });
    }
}
%end

// 添加对设置变化的响应：当用户通过双指长按改变设置时，重新应用
// 由于设置了 NSUserDefaults，我们可以在每次 viewDidAppear 时重新应用
// 为了更及时，可以在双指长按的回调中直接调用 HGProcessAllWindows

// 添加双指长按手势（在 UIWindow 上）
%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self && HGShouldApply()) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hg_handleLongPress:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
    }
    return self;
}

%new
- (void)hg_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    UIViewController *topVC = [self rootViewController];
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    BOOL fullscreen = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreen"];
    BOOL hideTab = [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoHideTabBar"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果设置"
                                                                   message:[NSString stringWithFormat:@"全屏：%@\n隐藏底栏：%@", fullscreen ? @"开" : @"关", hideTab ? @"开" : @"关"]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 全屏", fullscreen ? @"关闭" : @"开启"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !fullscreen;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoFullScreen"];
                                                // 应用全屏
                                                HGProcessAllWindows();
                                                [self hg_showToast:[NSString stringWithFormat:@"全屏已%@", newVal ? @"开启" : @"关闭"]];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 底栏", hideTab ? @"显示" : @"隐藏"]
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
                                                BOOL newVal = !hideTab;
                                                [[NSUserDefaults standardUserDefaults] setBool:newVal forKey:@"HongGuoHideTabBar"];
                                                // 应用隐藏底栏
                                                HGProcessAllWindows();
                                                [self hg_showToast:[NSString stringWithFormat:@"底栏已%@", newVal ? @"隐藏" : @"显示"]];
                                            }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds), 0, 0);
    }

    [topVC presentViewController:alert animated:YES completion:nil];
}

%new
- (void)hg_showToast:(NSString *)msg {
    UIViewController *top = [self rootViewController];
    while (top.presentedViewController) {
        top = top.presentedViewController;
    }
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}
%end

%ctor {
    if (HGShouldApply()) {
        dispatch_async(dispatch_get_main_queue(), ^{
            HGProcessAllWindows();
        });
    }
}
