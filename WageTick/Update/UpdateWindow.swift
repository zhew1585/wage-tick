import AppKit
import Observation
import SwiftUI

/// 更新窗口要显示的一屏 (设计稿「App 内更新 · 4 个界面」)。每一屏带着它的按钮动作；点红色关闭按钮等同于 `dismiss`。
enum UpdateScreen {
    /// ① 发现新版本：版本号、当前版本、更新内容；以后再说 / 下载更新。
    case found(version: String, current: String, notes: [String], later: () -> Void, download: () -> Void)
    /// ② 下载中：已下载与总大小 (总大小未知时为 0)；取消下载。
    case downloading(version: String, received: UInt64, expected: UInt64, cancel: () -> Void)
    /// ② 下载完在解压，没有可点的按钮。
    case extracting(version: String)
    /// ③ 已准备好：自动更新下载完也弹这个；稍后自行重启 / 立即重启。
    case ready(version: String, notes: [String], later: () -> Void, restart: () -> Void)
    /// ④ 已是最新版：版本号与构建号 (如「0.1.1」「42」，开发时可能没有构建号)。
    case upToDate(current: String, build: String? = nil, ok: () -> Void)
    /// 检查或下载出错 (设计稿之外，沿用 ④ 的样子)。
    case failed(message: String, ok: () -> Void)

    /// 点关闭按钮时做什么：等同于「以后再说 / 取消 / 稍后 / 好」。
    var dismiss: (() -> Void)? {
        switch self {
        case .found(_, _, _, let later, _): later
        case .downloading(_, _, _, let cancel): cancel
        case .extracting: nil
        case .ready(_, _, let later, _): later
        case .upToDate(_, _, let ok), .failed(_, let ok): ok
        }
    }
}

/// 更新窗口：宽 360、高随内容，顶上是 210 高的彩色头图 (红绿灯画在它上面)，见 `UpdateView`。
/// 同一时间只有一个，换屏时原地刷新；点按钮或关闭都会先把这一屏的回调交还给 Sparkle 再关窗。
///
/// 用法：`UpdateWindowController.shared.show(.ready(...))`，`close()` 关窗而不触发回调。
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()

    @Observable
    final class Model {
        var screen: UpdateScreen?
    }

    private let model = Model()
    private lazy var window: NSWindow = makeWindow()
    /// 已经交还了回调 (点了按钮或代码关窗)，关窗时不再触发 `dismiss`。
    private var handled = false

    func show(_ screen: UpdateScreen) {
        model.screen = screen
        handled = false
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// 刷新当前一屏 (如下载进度)，不抢焦点。窗口没开时不弹出来。
    func update(_ screen: UpdateScreen) {
        guard window.isVisible else { return }
        model.screen = screen
    }

    var isShowing: Bool { window.isVisible }

    func close() {
        handled = true
        window.close()
    }

    /// 按钮回调：先关窗，再交还给 Sparkle。
    fileprivate func perform(_ action: @escaping () -> Void) {
        close()
        action()
    }

    func windowWillClose(_ notification: Notification) {
        guard !handled else { return }
        handled = true
        model.screen?.dismiss?()
    }

    private func makeWindow() -> NSWindow {
        let view = UpdateView(model: model) { [weak self] action in self?.perform(action) }
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        controller.safeAreaRegions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "更新"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // 同其他窗口的紧凑标题栏 (`WindowChrome.Titlebar.compact`)：红绿灯离窗口边留出 8 以上。
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = NSColor(Palette.bg)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
