import AppKit
import SwiftUI

/// 目标、历史、设置窗口共用的外观 (设计稿 P3 至 P6)：系统红绿灯 + 透明的高标题栏 (`WindowChrome`，`.tall`)，
/// 内容顶到窗口上沿，页头由 SwiftUI 的 `PageHeader` 画，和红绿灯排在同一行 (返回箭头在红绿灯右边，返回即关窗)；
/// 窗口底色 bg，拖顶部标题栏 (页头那一条的空白处) 移动窗口，固定尺寸 (`WindowMetrics`)，页头下面的内容放不下时滚动 (`ScrollBody`)。
///
/// 用法 (窗口控制器里)：`PageWindow.make(title: "目标", rootView: view, delegate: self)`。
@MainActor
enum PageWindow {
    static func make(title: String, rootView: some View, delegate: NSWindowDelegate) -> NSWindow {
        // 内容画到透明标题栏底下，页头顶到窗口上沿。
        let window = WindowChrome.makeWindow(title: title, titlebar: .tall, rootView: rootView)
        window.delegate = delegate
        return window
    }
}
