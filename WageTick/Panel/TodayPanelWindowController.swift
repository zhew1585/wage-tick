import AppKit
import Observation
import OSLog
import SwiftUI
import WageCore

/// 面板当前要展示的内容，由窗口控制器按快照刷新，视图只读。
@MainActor
@Observable
final class TodayPanelContent {
    var panel: TodayPanel?
    /// 面板上的按钮发命令用，如白干计时的开始与停止。
    var send: (Command) -> Void = { _ in }
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
    /// 命令改了状态后通知外壳其余部分 (菜单栏小牛) 立即重绘。
    private let onStateChange: () -> Void
    private let content = TodayPanelContent()
    private lazy var window: NSWindow = makeWindow()
    private var timer: Timer?
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "TodayPanel")

    init(model: AppModel, onStateChange: @escaping () -> Void) {
        self.model = model
        self.onStateChange = onStateChange
        super.init()
        content.send = { [weak self] command in self?.send(command) }
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
        scheduleNextRefresh(rolling: snap.today?.isRolling == true)
    }

    /// 发出面板按钮的命令，并立即重绘面板与菜单栏。
    /// 按钮只在快照允许时出现，被拒多半是界面落后于时钟 (如刚过 23:59:59)，记日志后按最新快照重绘即可。
    private func send(_ command: Command) {
        do {
            try model.send(command)
        } catch {
            logger.error("面板命令被拒绝：\(error.message, privacy: .public)")
        }
        refresh()
        onStateChange()
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: TodayPanelView(content: content)))
        window.title = "今日概览"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
