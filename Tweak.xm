// =============================================================
//  HongGuoFullScreen — 完整版（过滤+黑块修复+隐藏顶部+诊断）
//  1. 强制拦截所有 setItems，只保留首页和我的
//  2. 在 viewDidAppear 后设置 barTintColor + alpha=1（消除黑块）
//  3. 不移改 frame，避免空白
//  4. 进入“我的”页面时自动隐藏顶部多余区域（尝试性）
//  5. 诊断视图层级，日志保存至 Documents/viewHierarchy.log
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <stdarg.h>

// ---------- 诊断日志 ----------
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

// ---------- 开关 ----------
static BOOL isEnabled() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"HongGuoFullScreenEnabled"];
}

static NSInteger defaultTabIndex() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"HongGuoDefaultTab"];
}

static NSInteger indexOfMyVC(NSArray *vcs) {
    for (NSInteger i = 0; i < vcs.count; i++) {
        UIViewController *vc = vcs[i];
        NSString *title = vc.tabBarItem.title;
        if ([title isEqualToString:@"我的"]) {
            return i;
        }
    }
    return -1;
}

// ---------- 诊断：记录 tabBar 状态 ----------
static void logTabBarState(UITabBar *tabBar, NSString *tag) {
    if (!tabBar) return;
    WriteLog(@"  [%@] alpha=%.3f frame=%@ barTintColor=%@ itemsCount=%lu",
             tag,
             tabBar.alpha,
             NSStringFromCGRect(tabBar.frame),
             tabBar.barTintColor ?: @"nil",
             (unsigned long)tabBar.items.count);
}

// ---------- 获取当前页面背景色 ----------
static UIColor *getCurrentPageBackgroundColor(UITabBarController *tab) {
    UIViewController *selected = tab.selectedViewController;
    if (!selected) return [UIColor whiteColor];
    UIColor *color = selected.view.backgroundColor;
    if (color) return color;
    CGColorRef layerColor = selected.view.layer.backgroundColor;
    if (layerColor) return [UIColor colorWithCGColor:layerColor];
    return [UIColor whiteColor];
}

// ---------- 强制过滤 items（保证只有首页和我的） ----------
static NSArray *filterItems(NSArray *items) {
    if (!isEnabled() || items.count <= 2) return items;
    NSMutableArray *filtered = [NSMutableArray array];
    for (UITabBarItem *item in items) {
        NSString *title = item.title;
        if ([title isEqualToString:@"首页"] || [title isEqualToString:@"我的"]) {
            [filtered addObject:item];
        }
    }
    return filtered;
}

// ---------- 修复 tabBar（设置颜色 + alpha） ----------
static void fixTabBar(UITabBarController *tab) {
    if (!tab) return;
    UITabBar *tabBar = tab.tabBar;

    // 1. 强制设置 barTintColor（匹配背景）
    UIColor *bgColor = getCurrentPageBackgroundColor(tab);
    if (bgColor) {
        tabBar.barTintColor = bgColor;
        tabBar.translucent = NO;
        WriteLog(@"fixTabBar: 设置 barTintColor = %@", bgColor);
    }

    // 2. 设置 alpha=1（消除黑块）
    if (tabBar.alpha != 1.0) {
        tabBar.alpha = 1.0;
        WriteLog(@"fixTabBar: 设置 alpha = 1.0");
    }

    // 3. 刷新背景视图
    id backgroundView = [tabBar valueForKey:@"_backgroundView"];
    if (backgroundView && [backgroundView respondsToSelector:@selector(setNeedsDisplay)]) {
        [backgroundView performSelector:@selector(setNeedsDisplay)];
    }

    [tabBar setNeedsLayout];
    [tabBar layoutIfNeeded];

    logTabBarState(tabBar, @"fixTabBar 完成");
}

// =============================================================
// 新增：视图层级诊断 + 隐藏顶部区域
// =============================================================

// 递归打印视图层级
static void dumpViewHierarchy(UIView *view, NSInteger depth, NSMutableString *output) {
    if (!view) return;
    NSString *indent = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *classStr = NSStringFromClass([view class]);
    NSString *frameStr = NSStringFromCGRect(view.frame);
    NSString *text = @"";
    if ([view isKindOfClass:[UILabel class]]) {
        text = [(UILabel *)view text] ?: @"";
    } else if ([view isKindOfClass:[UIButton class]]) {
        text = [(UIButton *)view titleForState:UIControlStateNormal] ?: @"";
    }
    [output appendFormat:@"%@%@ frame=%@ text=%@\n", indent, classStr, frameStr, text];
    for (UIView *sub in view.subviews) {
        dumpViewHierarchy(sub, depth + 1, output);
    }
}

static void logMyPageViewHierarchy(UIViewController *vc) {
    NSMutableString *output = [NSMutableString string];
    [output appendString:@"========== My Page View Hierarchy ==========\n"];
    dumpViewHierarchy(vc.view, 0, output);
    WriteLog(@"%@", output); // 也会输出到控制台
    // 额外写入单独文件便于提取
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = [paths firstObject];
    NSString *filePath = [docPath stringByAppendingPathComponent:@"viewHierarchy.log"];
    [output writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    WriteLog(@"视图层级已保存至: %@", filePath);
}

// 尝试隐藏“我的”页面顶部多余区域（基于文本匹配 + 父容器隐藏）
static void hideTopAreaInMyPage(UIViewController *myVC) {
    if (!myVC || !isEnabled()) return;

    // 定义可能出现在顶部区域的敏感文本（可依据日志调整）
    NSArray *keywords = @[@"爆款", @"上新", @"娘为小师妹撑腰", @"四季"];

    // 获取顶层视图
    UIView *rootView = myVC.view;
    if (!rootView) return;

    // 首先尝试找到包含这些文本的 UILabel，然后获取其父视图并隐藏
    BOOL found = NO;
    for (UIView *subview in [self allSubviewsOfView:rootView]) {
        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            NSString *text = label.text;
            if (text.length > 0) {
                for (NSString *kw in keywords) {
                    if ([text rangeOfString:kw].location != NSNotFound) {
                        // 找到匹配的标签，尝试隐藏其父视图（可能为容器）
                        UIView *parent = label.superview;
                        // 向上查找，直到找到一个非 UITableView 且非 UICollectionView 的父视图，但高度较大的
                        while (parent && ![parent isKindOfClass:[UITableView class]] && ![parent isKindOfClass:[UICollectionView class]]) {
                            // 如果父视图高度超过 80，很可能就是顶部横幅容器
                            if (parent.frame.size.height > 80) {
                                WriteLog(@"隐藏顶部容器: %@ frame=%@", NSStringFromClass([parent class]), NSStringFromCGRect(parent.frame));
                                parent.hidden = YES;
                                found = YES;
                                break;
                            }
                            parent = parent.superview;
                        }
                        if (found) break;
                    }
                }
            }
            if (found) break;
        }
    }

    // 如果没找到，尝试另一种策略：直接隐藏第一个非滚动、高度较大的子视图
    if (!found) {
        for (UIView *sub in rootView.subviews) {
            if (![sub isKindOfClass:[UIScrollView class]] && ! [sub isKindOfClass:[UITableView class]] && ! [sub isKindOfClass:[UICollectionView class]]) {
                if (sub.frame.size.height > 100 && sub.frame.origin.y < 50) {
                    WriteLog(@"直接隐藏顶部大视图: %@ frame=%@", NSStringFromClass([sub class]), NSStringFromCGRect(sub.frame));
                    sub.hidden = YES;
                    found = YES;
                    break;
                }
            }
        }
    }

    if (!found) {
        WriteLog(@"未找到可隐藏的顶部区域，请查看 viewHierarchy.log 手动调整关键词或类名");
    }
}

// 辅助：遍历所有子视图（包括深层）
static NSArray *allSubviewsOfView(UIView *view) {
    NSMutableArray *result = [NSMutableArray array];
    [self addAllSubviews:view toArray:result];
    return result;
}

static void addAllSubviews(UIView *view, NSMutableArray *array) {
    [array addObject:view];
    for (UIView *sub in view.subviews) {
        addAllSubviews(sub, array);
    }
}

// =============================================================
// Hook CYLTabBar — 拦截所有 setItems，强制过滤
// =============================================================
%hook CYLTabBar

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    NSArray *filtered = filterItems(items);
    WriteLog(@"CYLTabBar setItems: 原 count=%lu -> 过滤后 count=%lu", (unsigned long)items.count, (unsigned long)filtered.count);
    %orig(filtered, animated);
    // 过滤后立即修复 tabBar
    id responder = self;
    while (responder && ![responder isKindOfClass:[UITabBarController class]]) {
        responder = [responder nextResponder];
    }
    if ([responder isKindOfClass:[UITabBarController class]]) {
        fixTabBar((UITabBarController *)responder);
    }
}

// 只记录 setFrame，不修改
- (void)setFrame:(CGRect)frame {
    // 不修改 frame，只记录
    WriteLog(@"CYLTabBar setFrame: %@", NSStringFromCGRect(frame));
    %orig(frame);
}

%end

// =============================================================
// Hook SSTabBarController
// =============================================================
%hook SSTabBarController

- (void)viewDidLoad {
    %orig;
    WriteLog(@"SSTabBarController viewDidLoad");
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        if (tab.selectedIndex >= tab.viewControllers.count) {
            tab.selectedIndex = 0;
        }
        // 立即过滤一次
        NSArray *filtered = filterItems(tab.tabBar.items);
        if (filtered.count < tab.tabBar.items.count) {
            [tab.tabBar setItems:filtered animated:NO];
        }
        logTabBarState(tab.tabBar, @"viewDidLoad");
        fixTabBar(tab);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    if (isEnabled() && defaultTabIndex() == 1) {
        UITabBarController *tab = (UITabBarController *)self;
        NSArray *vcs = tab.viewControllers;
        NSInteger myIndex = indexOfMyVC(vcs);
        if (myIndex != -1 && tab.selectedIndex != myIndex) {
            WriteLog(@"viewWillAppear: 设置 selectedIndex 为 %ld (我的)", (long)myIndex);
            tab.selectedIndex = myIndex;
        }
    }
    %orig;
    if (isEnabled()) {
        // 再次过滤和修复
        UITabBarController *tab = (UITabBarController *)self;
        NSArray *filtered = filterItems(tab.tabBar.items);
        if (filtered.count < tab.tabBar.items.count) {
            [tab.tabBar setItems:filtered animated:NO];
        }
        fixTabBar(tab);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!isEnabled()) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        WriteLog(@"viewDidAppear: 开始延迟修复");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UITabBarController *tab = (UITabBarController *)self;
            // 再次过滤
            NSArray *filtered = filterItems(tab.tabBar.items);
            if (filtered.count < tab.tabBar.items.count) {
                [tab.tabBar setItems:filtered animated:NO];
            }
            fixTabBar(tab);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                fixTabBar(tab);
                WriteLog(@"viewDidAppear: 修复完成");
            });
        });
    });

    // ---- 新增：如果当前选中的是“我的”，执行隐藏和诊断 ----
    UITabBarController *tab = (UITabBarController *)self;
    UIViewController *selected = tab.selectedViewController;
    if ([selected.tabBarItem.title isEqualToString:@"我的"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // 诊断视图层级
            logMyPageViewHierarchy(selected);
            // 尝试隐藏顶部区域
            hideTopAreaInMyPage(selected);
        });
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        // 只修复颜色和 alpha，不修改 frame
        UIColor *bgColor = getCurrentPageBackgroundColor(tab);
        if (bgColor) {
            tab.tabBar.barTintColor = bgColor;
            tab.tabBar.translucent = NO;
        }
        if (tab.tabBar.alpha != 1.0) {
            tab.tabBar.alpha = 1.0;
        }
    }
}

- (void)setSelectedIndex:(NSInteger)selectedIndex {
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        NSArray *vcs = tab.viewControllers;
        if (selectedIndex >= vcs.count) {
            %orig(0);
            return;
        }
        UIViewController *targetVC = vcs[selectedIndex];
        NSString *title = targetVC.tabBarItem.title;
        if ([title isEqualToString:@"剧场"]) {
            NSInteger myIndex = indexOfMyVC(vcs);
            if (myIndex != -1) {
                WriteLog(@"setSelectedIndex: 重定向 '剧场' -> '我的'");
                %orig(myIndex);
                fixTabBar(tab);
                return;
            } else {
                %orig(0);
                return;
            }
        }
    }
    %orig(selectedIndex);
    if (isEnabled()) {
        UITabBarController *tab = (UITabBarController *)self;
        // 切换后确保过滤和修复
        NSArray *filtered = filterItems(tab.tabBar.items);
        if (filtered.count < tab.tabBar.items.count) {
            [tab.tabBar setItems:filtered animated:NO];
        }
        fixTabBar(tab);

        // ---- 如果切换到“我的”，同样执行隐藏和诊断 ----
        UIViewController *selectedVC = tab.selectedViewController;
        if ([selectedVC.tabBarItem.title isEqualToString:@"我的"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                logMyPageViewHierarchy(selectedVC);
                hideTopAreaInMyPage(selectedVC);
            });
        }
    }
}
%end

// =============================================================
// 双指双击菜单（含重启确认）
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

static void showDefaultTabMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"默认打开页面"
                                                                   message:@"选择应用启动时默认进入的页面"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSInteger current = defaultTabIndex();
    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 首页", current == 0 ? @"✓" : @""] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"HongGuoDefaultTab"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                         message:@"设置已保存，需要重启应用才能生效，是否立即重启？"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [restart addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        [restart addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:restart animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ 我的", current == 1 ? @"✓" : @""] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"HongGuoDefaultTab"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                         message:@"设置已保存，需要重启应用才能生效，是否立即重启？"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [restart addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            exit(0);
        }]];
        [restart addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:nil]];
        [topVC presentViewController:restart animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = window;
        alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds), 0, 0);
    }
    [topVC presentViewController:alert animated:YES completion:nil];
}

static void showSettingsMenu(UIWindow *window) {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;

    BOOL enabled = isEnabled();
    NSInteger defaultTab = defaultTabIndex();
    NSString *defaultText = defaultTab == 0 ? @"首页" : @"我的";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"红果精简Tab控制"
                                                                   message:[NSString stringWithFormat:@"当前状态：%@\n默认打开：%@", enabled ? @"已开启" : @"已关闭", defaultText]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:enabled ? @"关闭功能" : @"开启功能" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"提示"
                                                                         message:@"切换后需重启 App 生效，确定？"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[NSUserDefaults standardUserDefaults] setBool:!enabled forKey:@"HongGuoFullScreenEnabled"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            UIAlertController *restart = [UIAlertController alertControllerWithTitle:@"重启应用"
                                                                             message:@"是否立即重启？"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
            [restart addAction:[UIAlertAction actionWithTitle:@"立即重启" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                exit(0);
            }]];
            [restart addAction:[UIAlertAction actionWithTitle:@"稍后" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                showToast(@"请手动重启红果短剧", window);
            }]];
            UIViewController *top = window.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            [top presentViewController:restart animated:YES completion:nil];
        }]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:confirm animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"设置默认打开页面" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        showDefaultTabMenu(window);
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
        WriteLog(@"双指双击手势已添加");
    }
    return self;
}
%new
- (void)hg_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        if (@available(iOS 10.0, *)) {
            [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
        }
        WriteLog(@"用户触发双指双击菜单");
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
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"HongGuoDefaultTab"]) {
        [[NSUserDefaults standardUserDefaults] setInteger:0 forKey:@"HongGuoDefaultTab"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    WriteLog(@"HongGuoFullScreen 加载成功，默认打开：%@", defaultTabIndex() == 0 ? @"首页" : @"我的");
    WriteLog(@"========================================");
}
