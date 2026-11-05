import AppKit
import Observation
import SwiftUI
import WageCore

/// 面板当前要展示的内容，由窗口控制器按快照刷新，视图只读。
@MainActor
@Observable
final class TodayPanelContent {
    var panel: TodayPanel?
}

/// 今日概览面板窗口 (PRD F4，页面 P2)，从左键菜单「今日概览 ⌘1」打开。
/// 只在窗口可见时刷新：上班中按滚动频率，其余每秒一次 (倒计时、时钟)。
@MainActor
final class TodayPanelWindowController: NSObject, NSWindowDelegate {
    /// 上班中主数字滚动的刷新间隔，与菜单栏一致 (AC-BAR-02)。
    private static let rollingInterval: TimeInterval = 0.1
    /// 其他日状态只需让倒计时与时钟逐秒走 (AC-HOME-02)。
    private static let idleInterval: TimeInterval = 1

    private let model: AppModel
    private let content = TodayPanelContent()
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

    private func refresh() {
        let snap = model.currentSnapshot()
        content.panel = snap.panel
        scheduleNextRefresh(rolling: snap.today?.isEarning == true)
    }

    private func scheduleNextRefresh(rolling: Bool) {
        timer?.invalidate()
        let timer = Timer(timeInterval: rolling ? Self.rollingInterval : Self.idleInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func makeWindow() -> NSWindow {
        let actions = PanelActions(
            dryRun: { [model] command in model.dryRun(command) },
            send: { [weak self] command throws(CommandError) in
                guard let self else { return }
                try model.send(command)
                // 立即刷新，让今日已赚当场往下掉一截 (F5)，不等下一次定时刷新。
                refresh()
            }
        )
        let view = TodayPanelView(content: content, actions: actions)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "今日概览"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
