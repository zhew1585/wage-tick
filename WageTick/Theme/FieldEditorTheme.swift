import AppKit
import SwiftUI

/// 输入框的光标与选中底色用主题色：光标 accent，选中文字 accent-soft 底。
/// SwiftUI 的 `TextField` 在 macOS 上用的是窗口共用的字段编辑器 (field editor)，光标颜色不吃 `.tint`，
/// 所以在每个窗口成为 key window 时给它的字段编辑器上色。启动时调用一次 `install()`。
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

    /// 彩色头图里的输入框 (扣钱表单的大号金额) 用另一套：光标高亮黄，选中文字墨色半透明底 (白字在 accent-soft 上看不清)。
    /// 字段编辑器是整个窗口共用的，离开那个输入框时传 false 换回来。作用在当前 key window。
    static func useHeroStyle(_ on: Bool) {
        guard let window = NSApp.keyWindow else { return }
        if on {
            guard let editor = window.fieldEditor(true, for: nil) as? NSTextView else { return }
            editor.insertionPointColor = NSColor(Palette.highlight)
            editor.selectedTextAttributes = [.backgroundColor: NSColor(Palette.ink).withAlphaComponent(0.25)]
        } else {
            apply(to: window)
        }
    }

    private static func apply(to window: NSWindow) {
        guard let editor = window.fieldEditor(true, for: nil) as? NSTextView else { return }
        editor.insertionPointColor = NSColor(Palette.accent)
        editor.selectedTextAttributes = [.backgroundColor: NSColor(Palette.accentSoft)]
    }
}
