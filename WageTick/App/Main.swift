import AppKit

/// 入口：纯菜单栏 App (Info.plist 里 LSUIElement = YES，不出现在 Dock)。
@main
enum Main {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
