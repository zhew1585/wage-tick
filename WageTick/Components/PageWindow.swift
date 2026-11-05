import AppKit
import SwiftUI

/// 目标、历史、设置窗口共用的外观 (设计稿 P3 至 P6)：
/// 不显示系统标题与红绿灯，标题栏透明、内容顶到窗口上沿，页头由 SwiftUI 的 `PageHeader` 画 (返回箭头即关窗)；
/// 窗口底色 bg，拖动任意空白处移动窗口，大小跟着内容走。
///
/// 用法 (窗口控制器里)：`PageWindow.make(title: "目标", rootView: view, delegate: self)`。
@MainActor
enum PageWindow {
    static func make(title: String, rootView: some View, delegate: NSWindowDelegate) -> NSWindow {
        let controller = NSHostingController(rootView: rootView.background(Palette.bg))
        // 不让出标题栏的安全区：内容画到透明标题栏底下，页头顶到窗口上沿，窗口高度正好等于内容高度。
        controller.safeAreaRegions = []
        let window = NSWindow(contentViewController: controller)
        // 标题不显示，仍给辅助功能与窗口列表用。
        window.title = title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Palette.bg)
        window.isReleasedWhenClosed = false
        window.delegate = delegate
        return window
    }
}
