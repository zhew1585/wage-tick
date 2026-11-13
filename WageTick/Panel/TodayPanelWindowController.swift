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
    /// 正在播放的目标达成庆祝动画 (F9)；播放结束、点掉或关掉面板时清空。
    var celebration: GoalCelebration?
    /// 概览还是原地打开的表单；每次打开面板回到概览。
    var route: PanelRoute = .home {
        didSet { if route != .home { formSession += 1 } }
    }
    /// 每次打开扣钱、请假表单加 1，表单按它换新视图，不留上一次的输入。
    private(set) var formSession = 0
    /// 钉住：窗口始终浮在其他窗口之上。由标题栏右侧的图钉按钮切换，记在偏好里，重启后保留。
    var isPinned = false
    /// 从右边推进来的页面 (历史、目标、设置)；nil 时显示概览 (或原地的表单)。
    var page: PanelPage?
}

/// 在今日概览窗口里推进来的页面。
enum PanelPage: Equatable {
    case history
    case goals
    case settings
}

/// 三个推进来的页面，由 App 建好交给面板。
@MainActor
struct PanelPages {
    let history: HistoryPage
    let goals: GoalsPage
    let settings: SettingsPage
}

/// 今日概览面板 (PRD F4，页面 P2)，从左键菜单、主菜单「今日概览 ⌘1」、Dock 图标或通知打开。
/// 也是唯一的主窗口：历史、目标、设置都在这里从右边推进来 (`show(page:)`、`PanelPage`)，返回或按 Esc 退回概览。
/// 普通窗口 (ADR-0005)：系统红绿灯，透明标题栏，固定尺寸 (`WindowMetrics`)，展开目标、打开表单时在窗口里滚动。
/// 没开着时打开的位置见 `WindowPlacement` (引导刚完成时接在引导窗口原位)；点红绿灯、按 Esc 或 ⌘W 关掉，失去焦点不收起。
/// 只在面板可见时刷新：上班中或白干中按滚动频率，其余每秒一次 (倒计时、时钟)。
/// 被别的窗口整个挡住、最小化、在别的桌面空间时停表 (`occlusionState`)，露出来时立即补一次再接着刷。
@MainActor
final class TodayPanelWindowController: NSObject, NSWindowDelegate {
    /// 上班中主数字滚动的刷新间隔，与菜单栏一致 (AC-BAR-02)。
    private static let rollingInterval: TimeInterval = 0.1
    /// 其他日状态只需让倒计时与时钟逐秒走 (AC-HOME-02)。
    private static let idleInterval: TimeInterval = 1

    private let model: AppModel
    /// 命令改了状态后通知外壳其余部分 (菜单栏小牛) 立即重绘，如白干计时开始后马上冒汗。
    private let onStateChange: () -> Void
    private let pages: PanelPages
    private let content = TodayPanelContent()
    private lazy var panel: PanelWindow = makePanel()
    private lazy var placement = WindowPlacement(window: panel, name: "TodayPanel")
    private var timer: Timer?
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "TodayPanel")

    init(
        model: AppModel,
        pages: PanelPages,
        onStateChange: @escaping () -> Void
    ) {
        self.model = model
        self.pages = pages
        self.onStateChange = onStateChange
    }

    /// 打开 (或从最小化恢复) 并前置。没开着时回到概览、摆好位置；开着或最小化时保持原样 (正在填的表单不丢)。
    /// `replacing`：接替的窗口 (引导) 的 frame，今日概览出现在它原来的位置，不跳。
    /// `page`：直接推到某一页 (菜单、主菜单、悬浮小牛的入口)；窗口没开着时不播动画，直接停在那一页。
    func show(replacing frame: NSRect? = nil, page: PanelPage? = nil) {
        let isOpen = panel.isVisible || panel.isMiniaturized
        if !isOpen {
            content.route = .home
        }
        if let page {
            if isOpen {
                push(page)
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { push(page) }
            }
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

    /// 点红绿灯或 ⌘W 关窗后停止刷新，推进来的页面也退掉。
    func windowWillClose(_ notification: Notification) {
        stop()
        if let page = content.page {
            lifecycle(page).disappear()
            content.page = nil
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if content.page == .settings { pages.settings.windowBecameKey() }
    }

    // MARK: 推入的页面

    /// 推到 `page`：已在别的页上时先退掉那一页，换成这一页。
    /// 从菜单推页面时概览上可能正开着扣钱、请假表单，先收起，免得它的 Esc、回车快捷键压在页面底下抢键。
    private func push(_ page: PanelPage) {
        guard content.page != page else { return }
        content.route = .home
        if let current = content.page { lifecycle(current).disappear() }
        lifecycle(page).appear()
        content.page = page
    }

    /// 退回概览。
    private func pop() {
        guard let page = content.page else { return }
        content.page = nil
        lifecycle(page).disappear()
    }

    private func lifecycle(_ page: PanelPage) -> (appear: () -> Void, disappear: () -> Void) {
        switch page {
        case .history: (pages.history.appear, pages.history.disappear)
        case .goals: (pages.goals.appear, pages.goals.disappear)
        case .settings: (pages.settings.appear, pages.settings.disappear)
        }
    }

    private func pageView(_ page: PanelPage) -> AnyView {
        let back = { [weak self] in self?.pop() ?? () }
        return switch page {
        case .history: AnyView(pages.history.view(back: back))
        case .goals: AnyView(pages.goals.view(back: back))
        case .settings: AnyView(pages.settings.view(back: back))
        }
    }

    /// 露出来时立即刷新并接着定时刷；看不见时 `scheduleNextRefresh` 不再排下一次，定时器自然停下。
    func windowDidChangeOcclusionState(_ notification: Notification) {
        if panel.occlusionState.contains(.visible) && timer == nil {
            refresh()
        }
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
        // 面板被挡住或正开着表单时先不播，免得牛马没看到就被确认掉；回到概览、露出来后下一次刷新再播。
        if let celebration = snap.celebration, content.route == .home, content.page == nil, panel.occlusionState.contains(.visible) {
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
        timer = nil
        guard panel.occlusionState.contains(.visible) else { return }
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
        // 底部入口 (历史、目标、设置) 在这个窗口里把页面从右边推进来。
        let navigation = PanelNavigation(
            openHistory: { [weak self] in self?.push(.history) },
            openGoals: { [weak self] in self?.push(.goals) },
            openSettings: { [weak self] in self?.push(.settings) }
        )
        // 内容顶到窗口上沿，彩色头图垫在红绿灯下面 (大胆版)；头图自己让出标题栏那一行。
        // 钉住按钮放在标题栏右侧，和红绿灯同一行；推进来的页面右上角有自己的按钮，那时不显示钉住。
        let view = TodayPanelView(
            content: content, actions: actions, navigation: navigation,
            page: { [weak self] page in self?.pageView(page) ?? AnyView(EmptyView()) }
        )
            .overlay(alignment: .topTrailing) {
                PinButton(content: content) { [weak self] in self?.togglePin() }
                    .frame(height: WindowChrome.Titlebar.hero.height)
                    .padding(.trailing, Spacing.s12)
            }
        let panel = WindowChrome.makeWindow(PanelWindow.self, title: "今日概览", titlebar: .hero, rootView: view)
        panel.delegate = self
        panel.onCancel = { [weak self] in
            guard let self, content.page != nil else { return false }
            pop()
            return true
        }
        content.isPinned = UserDefaults.standard.bool(forKey: Self.pinnedKey)
        applyPin(to: panel)
        return panel
    }

    // MARK: 钉住

    private static let pinnedKey = "todayPanelPinned"

    private func togglePin() {
        content.isPinned.toggle()
        UserDefaults.standard.set(content.isPinned, forKey: Self.pinnedKey)
        applyPin(to: panel)
    }

    /// 钉住时窗口提到浮动层级，切到别的 App 也留在最前；取消后回到普通层级。
    private func applyPin(to window: NSWindow) {
        window.level = content.isPinned ? .floating : .normal
    }
}

/// 标题栏右侧的图钉：未钉住为空心 muted，钉住为实心 accent。
private struct PinButton: View {
    let content: TodayPanelContent
    let toggle: () -> Void

    /// 推进来的页面右上角有自己的按钮 (历史日历的改工资、翻月)，那时不显示钉住。
    var body: some View {
        if content.page == nil { button }
    }

    private var button: some View {
        Button(action: toggle) {
            // 垫在各色头图上：白底小圆片托着，哪种主色上都看得清。
            PhosphorIcon(content.isPinned ? .pushPinFill : .pushPin, size: 12)
                .foregroundStyle(content.isPinned ? Palette.accent : Palette.ink)
                .frame(width: 20, height: 20)
                .background(.white.opacity(0.85), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.highlight(radius: Radius.r4, outset: 2))
        .help(content.isPinned ? "取消钉住" : "钉住：窗口始终在最前")
        .accessibilityLabel(content.isPinned ? "取消钉住" : "钉住")
    }
}

/// 今日概览窗口：按 Esc 先退回上一页 (推进来的页面)，在概览上再按才关窗 (表单里的 Esc 先被「算了」按钮接走，回到概览)。
private final class PanelWindow: NSWindow {
    /// 返回 true 表示已经退回一页，不关窗。
    var onCancel: () -> Bool = { false }

    override func cancelOperation(_ sender: Any?) {
        if !onCancel() { performClose(sender) }
    }
}
