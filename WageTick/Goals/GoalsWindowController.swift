import AppKit
import Observation
import SwiftUI
import WageCore

/// 目标管理当前要展示的列表，由窗口控制器按快照刷新，视图只读。
@MainActor
@Observable
final class GoalsContent {
    var rows: [GoalRow] = []
}

/// 目标管理窗口 (PRD F8，页面 P3)，从左键菜单「目标 ⌘2」或面板空目标区打开。
/// 只在窗口可见时每秒刷新一次，让累计中目标的累计额跟着走。
@MainActor
final class GoalsWindowController: NSObject, NSWindowDelegate {
    private static let refreshInterval: TimeInterval = 1

    private let model: AppModel
    private let content = GoalsContent()
    private lazy var window: NSWindow = makeWindow()
    private var timer: Timer?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        refresh()
        NSApp.activate()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    /// 执行目标命令 (新建、编辑、删除、排序)，成功后立即刷新列表。校验失败时抛出 `CommandError`，由视图展示提示。
    private func send(_ command: Command) throws(CommandError) {
        try model.send(command)
        refresh()
    }

    private func refresh() {
        content.rows = model.currentSnapshot().goals ?? []
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func makeWindow() -> NSWindow {
        let view = GoalsView(content: content) { [weak self] (command: Command) throws(CommandError) in
            try self?.send(command)
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "目标"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
