import AppKit
import Observation
import OSLog
import SwiftUI
import WageCore

/// 面板当前要展示的内容，由窗口控制器按快照刷新。
/// 视图只改 `route` (打开、关掉表单) 和在庆祝动画结束时清空 `celebration`，其余只读。
@MainActor
@Observable
final class TodayPanelContent {
    var panel: TodayPanel?
    /// 今天的日状态，用来给主数字配小标题 (今日已赚 / 今日结算)；未完成引导时为 nil。
    var status: DayStatus?
    /// 请假入口 (F6)；nil 时今天不能请假。
    var leaveForm: LeaveForm?
    /// 底部入口栏右侧的老板路过快捷键，如「⌃⌥B」。
    var bossHotkey: String?
    /// 正在播放的目标达成庆祝动画 (F9)；播放结束、点掉或关掉面板时清空。
    var celebration: GoalCelebration?
    /// 概览还是原地打开的表单；每次打开面板回到概览。
    var route: PanelRoute = .home
}

/// 今日概览面板 (PRD F4，页面 P2)，从左键菜单、主菜单「今日概览 ⌘1」、Dock 图标或通知打开。
/// 普通窗口 (ADR-0005)：系统红绿灯，透明标题栏，固定尺寸 (`WindowMetrics`)，展开目标、打开表单时在窗口里滚动。
/// 没开着时打开的位置见 `WindowPlacement` (引导刚完成时接在引导窗口原位)；点红绿灯、按 Esc 或 ⌘W 关掉，失去焦点不收起。
/// 只在面板可见时刷新：上班中或白干中按滚动频率，其余每秒一次 (倒计时、时钟)。
@MainActor
final class TodayPanelWindowController: NSObject, NSWindowDelegate {
    /// 上班中主数字滚动的刷新间隔，与菜单栏一致 (AC-BAR-02)。
    private static let rollingInterval: TimeInterval = 0.1
    /// 其他日状态只需让倒计时与时钟逐秒走 (AC-HOME-02)。
    private static let idleInterval: TimeInterval = 1

    private let model: AppModel
    /// 命令改了状态后通知外壳其余部分 (菜单栏小牛) 立即重绘，如白干计时开始后马上冒汗。
    private let onStateChange: () -> Void
    private let navigation: PanelNavigation
    private let content = TodayPanelContent()
    private lazy var panel: PanelWindow = makePanel()
    private lazy var placement = WindowPlacement(window: panel, name: "TodayPanel")
    private var timer: Timer?
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "TodayPanel")

    init(
        model: AppModel,
        navigation: PanelNavigation,
        onStateChange: @escaping () -> Void
    ) {
        self.model = model
        self.navigation = navigation
        self.onStateChange = onStateChange
    }

    /// 打开 (或从最小化恢复) 并前置。没开着时回到概览、摆好位置；开着或最小化时保持原样 (正在填的表单不丢)。
    /// `replacing`：接替的窗口 (引导) 的 frame，今日概览出现在它原来的位置，不跳。
    func show(replacing frame: NSRect? = nil) {
        let isOpen = panel.isVisible || panel.isMiniaturized
        if !isOpen {
            content.route = .home
        }
        refresh()
        NSApp.activate()
        if !isOpen {
            if let frame {
                placement.place(replacing: frame)
            } else {
                placement.place()
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    /// 点红绿灯、按 Esc 或 ⌘W 关窗后停止刷新。
    func windowWillClose(_ notification: Notification) {
        stop()
    }

    // MARK: 刷新

    private func stop() {
        timer?.invalidate()
        timer = nil
        content.celebration = nil
    }

    private func refresh() {
        let snap = model.currentSnapshot()
        content.panel = snap.panel
        content.status = snap.today?.status
        content.leaveForm = snap.leaveForm
        content.bossHotkey = snap.settings.bossModeHotkey.displayText
        // 面板被挡住或正开着表单时先不播，免得牛马没看到就被确认掉；回到概览、露出来后下一次刷新再播。
        if let celebration = snap.celebration, content.route == .home, panel.occlusionState.contains(.visible) {
            play(celebration)
        }
        scheduleNextRefresh(rolling: snap.today?.isRolling == true)
    }

    /// 庆祝动画只播放一次 (AC-GPRG-04)：开始播放就向核心确认，之后的快照里不再有它。
    /// 正在播放上一个时先不接新的；新的没确认，播完后下一次刷新再播。刚打开面板的那次刷新面板还没露出来，下一次刷新 (至多 1 秒) 开始播。
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

    // MARK: 窗口

    private func makePanel() -> PanelWindow {
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
        // 面板是普通窗口，底部入口打开别的窗口时面板留着，牛马可以从 Dock、⌘Tab 或窗口菜单切回来。
        // 顶部整条让出标准标题栏 (28) 放红绿灯，下面按设计稿排。
        let view = TodayPanelView(content: content, actions: actions, navigation: navigation)
            .padding(.top, WindowChrome.Titlebar.standard.height)
        let panel = WindowChrome.makeWindow(PanelWindow.self, title: "今日概览", titlebar: .standard, rootView: view)
        panel.delegate = self
        return panel
    }
}

/// 今日概览窗口：按 Esc 关窗 (表单里的 Esc 先被「算了」按钮接走，回到概览)。
private final class PanelWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}
