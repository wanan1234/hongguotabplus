// =============================================================
//  HongGuoFullScreen — 精简 TabBar（只 Hook SSTabBar）
//  不依赖 SSTabBarController 的属性，完全规避编译问题
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

// =============================================================
// Hook SSTabBar（红果自定义 TabBar）
// =============================================================
%hook SSTabBar

- (void)setItems:(NSArray *)items animated:(BOOL)animated {
    WriteLog(@"SSTabBar setItems called, items count: %lu", (unsigned long)items.count);
    
    // 打印每个 item 的标题
    for (NSInteger i = 0; i < items.count; i++) {
        UITabBarItem *item = items[i];
        WriteLog(@"  [%ld] %@", (long)i, item.title ?: @"(无)");
    }
    
    // 如果 items 数量大于 2，只保留首页和我的（索引0和4）
    if (items.count > 2) {
        // 注意：这里我们直接使用索引0和4，这是根据红果的固定布局
        // 如果索引4不是“我的”，需要改用标题匹配
        NSArray *filtered = @[items[0], items[4]];
        WriteLog(@"Filtering items to: %@, %@", [items[0] title], [items[4] title]);
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
    WriteLog(@"========================================");
    WriteLog(@"HongGuoFullScreen 加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
}
