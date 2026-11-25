// 界面检查的注入库：经 DYLD_INSERT_LIBRARIES 加载进 Debug 版 App (要关掉 hardened runtime)，由 ui-checks-mac.sh 编译。
// 两种用法，看环境变量：
// - WAGETICK_RENDER_DIR：调用 App 里 Debug 才有的离屏渲染入口 (默认 wagetick_render_page_previews，可用 WAGETICK_RENDER_ENTRY 换)，渲染完退出。
// - WAGETICK_DRIVE_SOCKET：App 照常启动；本库在这个 Unix 套接字上一行一个地收命令，在主线程上合成按键、点击、截窗口图、读窗口状态，
//   每条命令回一行 JSON。命令见 `handle`。驱动方是 ui_drive.py。
// 两种用法都拦截 getpwuid：WAGETICK_FAKE_HOME 给了时把主目录换成它 (WidgetPayload 按 getpwuid 取真实主目录)，
// 配合 CFFIXED_USER_HOME，App 只读写临时目录里的假数据。
#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <pwd.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

#pragma mark 主目录

static struct passwd fakeEntry;

/// getpwuid 的替身：查到的账户信息里主目录换成假的。
static struct passwd *fake_getpwuid(uid_t uid) {
    struct passwd *real = getpwuid(uid);
    const char *home = getenv("WAGETICK_FAKE_HOME");
    if (!real || !home) return real;
    fakeEntry = *real;
    fakeEntry.pw_dir = (char *)home;
    return &fakeEntry;
}

__attribute__((used, section("__DATA,__interpose"))) static const struct {
    const void *replacement;
    const void *original;
} interposers[] = {{(const void *)fake_getpwuid, (const void *)getpwuid}};

#pragma mark 离屏渲染

static void *appDebugLibrary(void) {
    char exe[4096];
    uint32_t size = sizeof(exe);
    _NSGetExecutablePath(exe, &size);
    *strrchr(exe, '/') = 0;
    char lib[4200];
    snprintf(lib, sizeof(lib), "%s/WageTick.debug.dylib", exe);
    return dlopen(lib, RTLD_NOW);
}

static void render(const char *dir) {
    void *handle = appDebugLibrary();
    if (!handle) { fprintf(stderr, "%s\n", dlerror()); exit(2); }
    const char *name = getenv("WAGETICK_RENDER_ENTRY");
    void (*entry)(const char *) = dlsym(handle, name ? name : "wagetick_render_page_previews");
    if (!entry) { fprintf(stderr, "没找到渲染入口 %s，要用 Debug 构建\n", name ? name : "wagetick_render_page_previews"); exit(3); }
    entry(dir);
    exit(0);
}

#pragma mark 驱动

/// 今日概览窗口：标题是「今日概览」的那个 (表单 sheet 是另外的窗口)。
static NSWindow *panelWindow(void) {
    for (NSWindow *window in NSApp.windows) {
        if ([window.title isEqualToString:@"今日概览"]) return window;
    }
    return nil;
}

static NSString *json(id object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

/// 窗口状态：可见、挂着的 sheet、是不是 key、App 是否在前台，以及窗口的身份 (同一个窗口编号不变)。
static NSDictionary *windowState(void) {
    NSWindow *window = panelWindow();
    NSMutableArray *visible = [NSMutableArray array];
    for (NSWindow *other in NSApp.windows) {
        if (other.isVisible && other.styleMask & NSWindowStyleMaskTitled) [visible addObject:other.title ?: @""];
    }
    if (!window) return @{@"exists": @NO, @"visibleTitled": visible, @"active": @(NSApp.isActive)};
    return @{
        @"exists": @YES,
        @"number": @(window.windowNumber),
        @"visible": @(window.isVisible),
        @"sheet": @(window.attachedSheet != nil),
        @"key": @(window.isKeyWindow),
        @"active": @(NSApp.isActive),
        @"width": @(window.frame.size.width),
        @"height": @(window.frame.size.height),
        @"visibleTitled": visible,
    };
}

/// 把窗框视图 (含系统红绿灯) 画进一张 2 倍的位图，不论屏幕是几倍；圆角外透明的地方铺上窗口底色。调用方负责释放。
static CGContextRef renderWindow(NSWindow *window) {
    NSView *frameView = window.contentView.superview;
    NSRect bounds = frameView.bounds;
    NSBitmapImageRep *rep = [frameView bitmapImageRepForCachingDisplayInRect:bounds];
    [frameView cacheDisplayInRect:bounds toBitmapImageRep:rep];
    size_t width = (size_t)(bounds.size.width * 2), height = (size_t)(bounds.size.height * 2);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space, kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(space);
    NSColor *background = [(window.backgroundColor ?: NSColor.windowBackgroundColor) colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    CGContextSetRGBFillColor(context, background.redComponent, background.greenComponent, background.blueComponent, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), rep.CGImage);
    return context;
}

/// 存一张今日概览窗口的 2 倍 PNG (整窗，含红绿灯)。
static NSString *snapshot(NSString *path) {
    NSWindow *window = panelWindow();
    if (!window) return @"没有今日概览窗口";
    CGContextRef context = renderWindow(window);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    CGImageRelease(image);
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path atomically:YES] ? nil : @"写不了图";
}

/// 窗口里一块区域 (相对左上角的 pt) 的墨迹指纹：亮度低于 `threshold` 的像素组成的形状的哈希与个数。
/// 只看深色的字与图标，悬停、按下时浅色的圆角底和红绿灯的颜色不影响；同一次运行里同一画面的指纹逐像素相同。
static NSDictionary *inkSignature(CGFloat x, CGFloat y, CGFloat w, CGFloat h, int threshold) {
    NSWindow *window = panelWindow();
    if (!window) return @{@"error": @"没有今日概览窗口"};
    CGContextRef context = renderWindow(window);
    const uint8_t *pixels = CGBitmapContextGetData(context);
    size_t width = CGBitmapContextGetWidth(context), height = CGBitmapContextGetHeight(context);
    size_t stride = CGBitmapContextGetBytesPerRow(context);
    size_t x0 = (size_t)MAX(0, x * 2), y0 = (size_t)MAX(0, y * 2);
    size_t x1 = MIN(width, (size_t)((x + w) * 2)), y1 = MIN(height, (size_t)((y + h) * 2));
    uint64_t hash = 1469598103934665603ULL;
    NSInteger ink = 0;
    for (size_t row = y0; row < y1; row++) {
        // 位图的第 0 行是图的最上面一行 (CGBitmapContext 的内存按自上而下排)。
        const uint8_t *line = pixels + row * stride;
        for (size_t col = x0; col < x1; col++) {
            const uint8_t *p = line + col * 4;
            int dark = (p[0] + p[1] + p[2]) / 3 < threshold;
            ink += dark;
            hash = (hash ^ (uint64_t)(dark ? (row * width + col + 1) : 0)) * 1099511628211ULL;
        }
    }
    CGContextRelease(context);
    return @{@"hash": [NSString stringWithFormat:@"%016llx", hash], @"ink": @(ink)};
}

/// 合成一次按键 (按下、抬起) 交给 NSApp，和真按键走同一条路：先给 key 窗口、再给主菜单的快捷键。
/// 目标是当前的 key 窗口 (开着 sheet 时是 sheet)，没有 key 窗口时是今日概览窗口。
static void pressKey(NSString *chars, unsigned short code, NSEventModifierFlags flags) {
    NSWindow *target = NSApp.keyWindow ?: panelWindow().attachedSheet ?: panelWindow();
    NSEventType types[] = {NSEventTypeKeyDown, NSEventTypeKeyUp};
    for (int i = 0; i < 2; i++) {
        NSEvent *event = [NSEvent keyEventWithType:types[i] location:NSZeroPoint modifierFlags:flags
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:target.windowNumber context:nil
            characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:code];
        [NSApp postEvent:event atStart:NO];
    }
}

/// 在今日概览窗口里点一下 (按下、抬起)：坐标是相对窗口左上角的 pt。事件排进 App 的事件队列，由 App 自己分发。
static void click(CGFloat x, CGFloat y) {
    NSWindow *window = panelWindow();
    NSPoint point = NSMakePoint(x, window.frame.size.height - y);
    NSEventType types[] = {NSEventTypeLeftMouseDown, NSEventTypeLeftMouseUp};
    for (int i = 0; i < 2; i++) {
        NSEvent *event = [NSEvent mouseEventWithType:types[i] location:point modifierFlags:0
            timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber context:nil
            eventNumber:0 clickCount:1 pressure:i == 0 ? 1 : 0];
        [NSApp postEvent:event atStart:NO];
    }
}

/// 辅助功能树 (进程内直接读，不需要系统授权)：每个元素的角色、文字、相对窗口左上角的 pt 框。被 accessibilityHidden 的不在里面。
static void collect(id element, NSWindow *window, NSMutableArray *out, int depth) {
    if (depth > 40 || ![element respondsToSelector:@selector(accessibilityChildren)]) return;
    for (id child in [element accessibilityChildren] ?: @[]) {
        NSString *label = [child respondsToSelector:@selector(accessibilityLabel)] ? [child accessibilityLabel] : nil;
        id value = [child respondsToSelector:@selector(accessibilityValue)] ? [child accessibilityValue] : nil;
        NSString *role = [child respondsToSelector:@selector(accessibilityRole)] ? [child accessibilityRole] : nil;
        NSRect screen = [child respondsToSelector:@selector(accessibilityFrame)] ? [child accessibilityFrame] : NSZeroRect;
        NSRect local = [window convertRectFromScreen:screen];
        [out addObject:@{
            @"role": role ?: @"",
            @"label": label ?: @"",
            @"value": [value isKindOfClass:NSString.class] ? value : @"",
            @"x": @(local.origin.x),
            @"y": @(window.frame.size.height - NSMaxY(local)),
            @"w": @(local.size.width),
            @"h": @(local.size.height),
        }];
        collect(child, window, out, depth + 1);
    }
}

/// 一条命令，返回一行 JSON。
static NSString *handle(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *command = parts.firstObject;
    if ([command isEqualToString:@"state"]) return json(windowState());
    if ([command isEqualToString:@"snap"] && parts.count > 1) {
        NSString *error = snapshot([[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@" "]);
        return json(error ? @{@"error": error} : @{@"ok": @YES});
    }
    if ([command isEqualToString:@"key"] && parts.count > 1) {
        // key cmd-1 | cmd-2 | cmd-3 | cmd-comma | esc
        NSDictionary *keys = @{
            @"cmd-1": @[@"1", @18], @"cmd-2": @[@"2", @19], @"cmd-3": @[@"3", @20], @"cmd-comma": @[@",", @43], @"esc": @[@"\x1b", @53],
        };
        NSArray *key = keys[parts[1]];
        if (!key) return json(@{@"error": @"不认识的键"});
        pressKey(key[0], [key[1] unsignedShortValue], [parts[1] hasPrefix:@"cmd-"] ? NSEventModifierFlagCommand : 0);
        return json(@{@"ok": @YES});
    }
    if ([command isEqualToString:@"click"] && parts.count > 2) {
        if (!panelWindow()) return json(@{@"error": @"没有今日概览窗口"});
        click(parts[1].doubleValue, parts[2].doubleValue);
        return json(@{@"ok": @YES});
    }
    if ([command isEqualToString:@"ax"]) {
        NSWindow *window = panelWindow();
        if (!window) return json(@{@"error": @"没有今日概览窗口"});
        // SwiftUI 平时不建辅助功能树，打开后才能按按钮的文字找到它在哪 (只在本进程里，不需要系统授权)。头一两次可能还是空的，由调用方重试。
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [NSApp accessibilitySetValue:@YES forAttribute:@"AXEnhancedUserInterface"];
#pragma clang diagnostic pop
        NSMutableArray *out = [NSMutableArray array];
        collect(window.contentView, window, out, 0);
        return json(@{@"elements": out});
    }
    if ([command isEqualToString:@"sig"] && parts.count > 5) {
        // sig x y w h 亮度阈值
        return json(inkSignature(parts[1].doubleValue, parts[2].doubleValue, parts[3].doubleValue, parts[4].doubleValue, parts[5].intValue));
    }
    if ([command isEqualToString:@"reopen"]) {
        // 点 Dock 图标时系统调的就是这个代理方法。
        id<NSApplicationDelegate> delegate = NSApp.delegate;
        if (![delegate respondsToSelector:@selector(applicationShouldHandleReopen:hasVisibleWindows:)]) return json(@{@"error": @"代理不处理重新打开"});
        [delegate applicationShouldHandleReopen:NSApp hasVisibleWindows:panelWindow().isVisible];
        return json(@{@"ok": @YES});
    }
    if ([command isEqualToString:@"quit"]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
        return json(@{@"ok": @YES});
    }
    return json(@{@"error": [@"不认识的命令：" stringByAppendingString:command ?: @""]});
}

/// 在套接字上一个连接一个连接地收命令；每条命令同步交给主线程执行。
static void serve(const char *path) {
    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    strlcpy(address.sun_path, path, sizeof(address.sun_path));
    unlink(path);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(server, 1) != 0) {
        fprintf(stderr, "驱动套接字打不开：%s\n", path);
        return;
    }
    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) continue;
        FILE *in = fdopen(client, "r");
        char *buffer = NULL;
        size_t capacity = 0;
        ssize_t length;
        while ((length = getline(&buffer, &capacity, in)) > 0) {
            NSString *line = [[[NSString alloc] initWithBytes:buffer length:length encoding:NSUTF8StringEncoding]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            __block NSString *reply;
            dispatch_sync(dispatch_get_main_queue(), ^{ reply = handle(line); });
            NSData *data = [[reply stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
            write(client, data.bytes, data.length);
        }
        free(buffer);
        fclose(in);
    }
}

__attribute__((constructor)) static void start(void) {
    const char *dir = getenv("WAGETICK_RENDER_DIR");
    if (dir) {
        render(dir);
        return;
    }
    const char *socketPath = getenv("WAGETICK_DRIVE_SOCKET");
    if (!socketPath) return;
    char *path = strdup(socketPath);
    [NSThread detachNewThreadWithBlock:^{ serve(path); }];
}
