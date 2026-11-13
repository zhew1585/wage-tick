import AppKit
import SwiftUI

/// 输入框的光标与选中底色用主题色：光标 accent，选中文字 accent-soft 底。
/// SwiftUI 的 `TextField` 在 macOS 上用的是窗口共用的字段编辑器 (field editor)，光标颜色不吃 `.tint`，
/// 所以在每个窗口成为 key window 时给它的字段编辑器上色。启动时调用一次 `install()`。
/// 注意：实测 SwiftUI 的 `TextField` 另有自己的字段编辑器，光标颜色跟 `.tint` 走 (默认是 AccentColor)；
/// 彩色头图里的大号输入框 (引导工资、扣钱金额、新目标金额) 用 `.tint(.white)` 换成白色光标。
@MainActor
enum FieldEditorTheme {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { apply(to: window) }
        }
    }

    private static func apply(to window: NSWindow) {
        guard let editor = window.fieldEditor(true, for: nil) as? NSTextView else { return }
        editor.insertionPointColor = NSColor(Palette.accent)
        editor.selectedTextAttributes = [.backgroundColor: NSColor(Palette.accentSoft)]
    }
}
