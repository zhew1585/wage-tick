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
    /// 请假入口 (F6)；nil 时今天不能请假。
    var leaveForm: LeaveForm?
    /// 正在播放的目标达成庆祝动画 (F9)；播放结束、点掉或关掉面板时清空。
    var celebration: GoalCelebration?
}

/// 今日概览面板窗口 (PRD F4，页面 P2)，从左键菜单「今日概览 ⌘1」打开。
/// 只在窗口可见时刷新：上班中或白干中按滚动频率，其余每秒一次 (倒计时、时钟)。
@MainActor
final class TodayPanelWindowController: NSObject, NSWindowDelegate {
    /// 上班中主数字滚动的刷新间隔，与菜单栏一致 (AC-BAR-02)。
    private static let rollingInterval: TimeInterval = 0.1
    /// 其他日状态只需让倒计时与时钟逐秒走 (AC-HOME-02)。
    private static let idleInterval: TimeInterval = 1

    private let model: AppModel
    /// 命令改了状态后通知外壳其余部分 (菜单栏小牛) 立即重绘，如白干计时开始后马上冒汗。
    private let onStateChange: () -> Void
    /// 点击空的目标区时打开目标管理 (F9)。
    private let openGoals: () -> Void
    private let content = TodayPanelContent()
    private lazy var window: NSWindow = makeWindow()
    private var timer: Timer?
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "TodayPanel")

    init(model: AppModel, openGoals: @escaping () -> Void, onStateChange: @escaping () -> Void) {
        self.model = model
        self.openGoals = openGoals
        self.onStateChange = onStateChange
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
        content.celebration = nil
    }

    private func refresh() {
        let snap = model.currentSnapshot()
        content.panel = snap.panel
        content.leaveForm = snap.leaveForm
        if let celebration = snap.celebration {
            play(celebration)
        }
        scheduleNextRefresh(rolling: snap.today?.isRolling == true)
    }

    /// 庆祝动画只播放一次 (AC-GPRG-04)：开始播放就向核心确认，之后的快照里不再有它。
    /// 正在播放上一个时先不接新的；新的没确认，播完后下一次刷新再播。
    private func play(_ celebration: GoalCelebration) {
        guard content.celebration == nil else { return }
        content.celebration = celebration
        do {
            try model.send(.acknowledgeCelebration(goalID: celebration.goalID))
        } catch {
            // 确认命令没有校验，正常不会被拒绝；万一被拒，下次打开面板会再播一次。
            logger.error("确认庆祝动画失败：\(error.message, privacy: .public)")
        }
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
                // 立即刷新，让今日已赚当场往下掉一截 (F5)、小牛当场冒汗 (F7)，不等下一次定时刷新。
                refresh()
                onStateChange()
            }
        )
        let view = TodayPanelView(content: content, actions: actions, openGoals: openGoals)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "今日概览"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
