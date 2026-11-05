import AppKit
import SwiftUI

/// 所有窗口共用的系统外框 (ADR-0005)：保留红绿灯，标题栏透明、内容铺满、不显示标题文字，底色 bg，拖顶部标题栏那一条移动窗口。
/// 所有窗口固定同一尺寸 (`WindowMetrics.size`)、不能拉伸，所以缩放按钮由系统自动置灰；内容放不下时在窗口里滚动。
///
/// 两种标题栏高度：
/// - `.standard`：系统默认 28 高，红绿灯在左上角 (今日概览面板、引导)。
/// - `.tall`：挂一个空的 unified 工具栏，标题栏 52 高，红绿灯垂直居中，正好和同高的 `PageHeader` 排成一行 (目标、历史、设置)。
///
/// 用法 (建窗口时)：`WindowChrome.makeWindow(title: "目标", titlebar: .tall, rootView: view)`；
/// 打开位置交给 `WindowPlacement`。
@MainActor
enum WindowChrome {
    enum Titlebar {
        case standard
        case tall

        /// 标题栏高度：要整条让出红绿灯的内容从这里往下排。
        var height: CGFloat {
            switch self {
            case .standard: 28
            case .tall: 52
            }
        }

        /// 和红绿灯同一行的内容的左边距：红绿灯右沿 (实测 standard 61、tall 73) 再空 12。
        var leadingInset: CGFloat {
            switch self {
            case .standard: 61 + Spacing.s12
            case .tall: 73 + Spacing.s12
            }
        }
    }

    /// 建一个固定尺寸的窗口：SwiftUI 内容铺满 (画到透明标题栏底下)，窗口不跟着内容变大小。
    /// `type` 给需要覆写按键处理的子类 (如今日概览按 Esc 关窗)。
    static func makeWindow<Window: NSWindow>(
        _ type: Window.Type = NSWindow.self, title: String, titlebar: Titlebar, rootView: some View
    ) -> Window {
        let size = WindowMetrics.size
        let controller = NSHostingController(rootView: rootView.frame(width: size.width, height: size.height).background(Palette.bg))
        // 不让出标题栏的安全区：内容顶到窗口上沿，要让出红绿灯的视图自己留位置 (`Titlebar.height`)。
        controller.safeAreaRegions = []
        // 窗口固定尺寸，不随 SwiftUI 内容的理想大小变。
        controller.sizingOptions = []
        let window = Window(contentViewController: controller)
        apply(to: window, title: title, titlebar: titlebar)
        window.setContentSize(size)
        return window
    }

    private static func apply(to window: NSWindow, title: String, titlebar: Titlebar) {
        // 标题不显示，仍给辅助功能、窗口菜单与 Mission Control 用。
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        if titlebar == .tall {
            window.toolbar = NSToolbar()
            window.toolbarStyle = .unified
        }
        // 只能拖顶部标题栏一条移动窗口：拖动空白处移动 (isMovableByWindowBackground) 会抢走目标排队列表的拖动排序。
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(Palette.bg)
        window.isReleasedWhenClosed = false
    }
}
