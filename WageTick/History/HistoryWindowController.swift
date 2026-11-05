import AppKit
import Observation
import SwiftUI
import WageCore

/// 历史窗口当前的快照，由窗口控制器刷新，视图只读。
/// 视图从它按需取月列表或某月日历：历史只在这个窗口打开时推导，不进菜单栏刷新的热路径。
@MainActor
@Observable
final class HistoryContent {
    var snapshot: Snapshot?
}

/// 历史窗口 (PRD F10、F11，页面 P4、P5)，从左键菜单「历史 ⌘3」打开。本票只读。
/// 只在窗口可见时每秒刷新一次：本月结算总额含今日已赚，要跟着本月累计走 (AC-HIS-01)。
@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private static let refreshInterval: TimeInterval = 1

    private let model: AppModel
    private let content = HistoryContent()
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
        // 关窗即丢掉快照，下次打开重新推导。
        content.snapshot = nil
    }

    private func refresh() {
        content.snapshot = model.currentSnapshot()
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: HistoryView(content: content)))
        window.title = "历史"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
