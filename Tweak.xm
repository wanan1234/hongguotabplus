// =============================================================
//  HongGuoFullScreen — 精简 TabBar（最终稳定版）
//  只过滤 SSTabBar 的 items，保留 viewControllers 完整
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>

// =============================================================
// Hook SSTabBar（红果自定义 TabBar）
// =============================================================
%hook SSTabBar

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    // 如果 items 数量大于 2，只保留首页和我的（索引0和4）
    if (items.count > 2) {
        NSArray *filtered = @[items[0], items[4]];
        %orig(filtered, animated);
        return;
    }
    %orig(items, animated);
}

%end

// =============================================================
// 构造函数
// =============================================================
%ctor {
    NSLog(@"[HongGuo] TabBar精简插件加载成功");
}
