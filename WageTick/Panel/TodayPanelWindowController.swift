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

/// 今日概览面板 (PRD F4，页面 P2)，从左键菜单「今日概览 ⌘1」或通知打开。
/// 像 popover 一样贴在菜单栏小牛下方弹出 (宽 360，设计稿 P2)；点面板外面、按 Esc 或切到别的 App 时收起。
/// 只在面板可见时刷新：上班中或白干中按滚动频率，其余每秒一次 (倒计时、时钟)。
@MainActor
final class TodayPanelWindowController: NSObject, NSWindowDelegate {
    /// 上班中主数字滚动的刷新间隔，与菜单栏一致 (AC-BAR-02)。
    private static let rollingInterval: TimeInterval = 0.1
    /// 其他日状态只需让倒计时与时钟逐秒走 (AC-HOME-02)。
    private static let idleInterval: TimeInterval = 1
    /// 面板顶边与菜单栏底边的间距。
    private static let anchorGap: CGFloat = 6
    /// 面板离屏幕边缘至少留这么多。
    private static let screenMargin: CGFloat = 8

    private let model: AppModel
    /// 命令改了状态后通知外壳其余部分 (菜单栏小牛) 立即重绘，如白干计时开始后马上冒汗。
    private let onStateChange: () -> Void
    private let navigation: PanelNavigation
    /// 菜单栏小牛按钮在屏幕上的位置，面板贴着它的下方弹出；拿不到时 (如菜单栏条目被系统藏起) 为 nil，面板放到屏幕右上角。
    private let anchor: () -> NSRect?
    private let content = TodayPanelContent()
    private lazy var panel: PopoverPanel = makePanel()
    private var timer: Timer?
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "TodayPanel")

    init(
        model: AppModel,
        navigation: PanelNavigation,
        anchor: @escaping () -> NSRect?,
        onStateChange: @escaping () -> Void
    ) {
        self.model = model
        self.navigation = navigation
        self.anchor = anchor
        self.onStateChange = onStateChange
    }

    func show() {
        if !panel.isVisible {
            content.route = .home
        }
        refresh()
        NSApp.activate()
        panel.layoutIfNeeded()
        position()
        panel.makeKeyAndOrderFront(nil)
        // 投影按内容形状 (圆角) 算，内容画出来后再算一次。
        panel.invalidateShadow()
    }

    /// 收起面板；打开底部入口里的窗口前先收起。
    func close() {
        panel.orderOut(nil)
        stop()
    }

    // MARK: NSWindowDelegate

    /// 点到面板外面 (包括别的 App、菜单栏) 时收起，像 popover 一样。
    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// 内容高度变了 (展开目标、打开表单) 后窗口跟着变高，顶边保持贴着菜单栏。
    func windowDidResize(_ notification: Notification) {
        position()
        panel.invalidateShadow()
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

    /// 顶边贴着菜单栏小牛下方，水平居中对准小牛，超出屏幕时往里收。
    private func position() {
        let size = panel.frame.size
        let screen = anchorScreen
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let top: CGFloat
        let centerX: CGFloat
        if let anchor = anchor() {
            top = anchor.minY - Self.anchorGap
            centerX = anchor.midX
        } else {
            top = visible.maxY - Self.anchorGap
            centerX = visible.maxX - size.width / 2 - Self.screenMargin
        }
        let minX = visible.minX + Self.screenMargin
        let maxX = visible.maxX - Self.screenMargin - size.width
        let x = min(max(centerX - size.width / 2, minX), max(minX, maxX))
        let origin = NSPoint(x: x.rounded(), y: (top - size.height).rounded())
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }

    /// 小牛所在的屏幕；拿不到小牛位置时用主屏。
    private var anchorScreen: NSScreen? {
        guard let anchor = anchor() else { return NSScreen.main }
        let point = NSPoint(x: anchor.midX, y: anchor.midY)
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func makePanel() -> PopoverPanel {
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
        // 底部入口打开别的窗口前先收起面板。
        let navigation = PanelNavigation(
            openHistory: { [weak self] in self?.close(); self?.navigation.openHistory() },
            openGoals: { [weak self] in self?.close(); self?.navigation.openGoals() },
            openSettings: { [weak self] in self?.close(); self?.navigation.openSettings() }
        )
        let view = TodayPanelView(content: content, actions: actions, navigation: navigation)
            .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius).strokeBorder(Palette.line, lineWidth: 1))
        // 默认的 sizingOptions 让窗口大小跟着 SwiftUI 内容走。
        let panel = PopoverPanel(contentViewController: NSHostingController(rootView: view))
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        return panel
    }
}

/// 无边框、透明底的浮动面板：圆角、描边由 SwiftUI 画，投影用系统窗口投影 (随内容形状)。
/// 无边框窗口默认不能成为 key window，这里放开，表单里的输入框才能打字。
private final class PopoverPanel: NSPanel {
    /// 按 Esc 时调用 (表单里的 Esc 先被「算了」按钮接走，回到概览)。
    var onCancel: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.contentViewController = contentViewController
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
