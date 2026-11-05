import AppKit

/// 入口：普通 App (出现在 Dock 与 ⌘Tab)，同时常驻菜单栏 (ADR-0005)。
@main
enum Main {
    @MainActor
    static func main() {
        // 先注册打包的字体，之后各处取字体才拿得到。
        AppFont.register()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
