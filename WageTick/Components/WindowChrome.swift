import AppKit
import SwiftUI

/// 所有窗口共用的系统外框 (ADR-0005)：保留红绿灯，标题栏透明、内容铺满、不显示标题文字，底色 bg，拖动空白处移动窗口。
/// 窗口大小跟着内容走、不能拉伸，所以缩放按钮由系统自动置灰。
///
/// 两种标题栏高度：
/// - `.standard`：系统默认 28 高，红绿灯在左上角 (今日概览面板、引导)。
/// - `.tall`：挂一个空的 unified 工具栏，标题栏 52 高，红绿灯垂直居中，正好和 54 高的 `PageHeader` 排成一行 (目标、历史、设置)。
///
/// 用法 (建窗口时)：`WindowChrome.apply(to: window, title: "目标", titlebar: .tall)`。
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

    static func apply(to window: NSWindow, title: String, titlebar: Titlebar) {
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
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Palette.bg)
        window.isReleasedWhenClosed = false
    }
}
