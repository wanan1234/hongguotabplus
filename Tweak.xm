#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================
// 双指长按弹出设置菜单
// =============================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hongguo_handleLongPress:)];
        gesture.numberOfTouchesRequired = 2;
        gesture.minimumPressDuration = 0.8;
        [self addGestureRecognizer:gesture];
    }
    return self;
}

%new
- (void)hongguo_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    // ... (处理逻辑与之前相同，此处省略以节省篇幅) ...
    // 请将之前实现的 hongguo_handleLongPress、hongguo_applyTabBar、hongguo_applyFullscreen、hongguo_showToast 方法完整复制到这里
}

%end

// =============================================
// Hook 红果的类（使用 %ctor 动态初始化）
// =============================================
%ctor {
    // 动态检测类是否存在，如果存在则进行 Hook
    if (NSClassFromString(@"SSTabBarController")) {
        %init(SSTabBarController);
    }
    if (NSClassFromString(@"SSVideoSeriesFeedViewController")) {
        %init(SSVideoSeriesFeedViewController);
    }
}

// 注意：这里不再使用 %group，而是直接使用 %hook
%hook SSTabBarController
- (void)viewDidLoad {
    %orig;
    // ... (实现代码) ...
}
%end

%hook SSVideoSeriesFeedViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    // ... (实现代码) ...
}
%end
