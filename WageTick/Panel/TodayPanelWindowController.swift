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
    var route: PanelRoute = .home
    /// 钉住：窗口始终浮在其他窗口之上。由标题栏右侧的图钉按钮切换，记在偏好里，重启后保留。
    var isPinned = false
    /// 从右边推进来的页面 (历史、目标、设置)；nil 时显示概览 (或原地的表单)。
    var page: PanelPage?
    /// 窗口看不看得见，与停表同一个判断 (`occlusionState` 含 `.visible`)；关窗时为 false。首页提示条据此停、开跑马灯。
    var isWindowVisible = false
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
/// 也是唯一的主窗口：历史、目标、设置都在这里从右边推进来 (`show(page:)`、`PanelPage`)，返回或按 Esc 一级一级退回概览。
/// 普通窗口 (ADR-0005)：系统红绿灯，透明的 52 高标题栏 (`.tall`，页面的页头与红绿灯同一行)，固定尺寸 (`WindowMetrics`)，内容放不下时在窗口里滚动。
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

    /// 打开 (或从最小化恢复) 并前置。没开着时回到概览、摆好位置。
    /// 开着或最小化时：没指定 `page` (今日概览 ⌘1、菜单栏「今日概览」、悬浮小牛、通知) 就从推进来的页面退回概览，
    /// 概览上正在填的扣钱、请假表单不动。只是把窗口找回来 (点 Dock 图标) 时传 `returnsToOverview: false`，停在哪页还在哪页。
    /// 页面上正开着弹出的表单 (新目标、设置里的各项、历史里的各项) 时，不管有没有指定 `page` 都只前置，不退页也不换页，免得没填完的丢了。
    /// `replacing`：接替的窗口 (引导) 的 frame，今日概览出现在它原来的位置，不跳。
    /// `page`：直接推到某一页 (菜单、主菜单 ⌘2 ⌘3 ⌘,、悬浮小牛的入口)；窗口没开着时不播动画，直接停在那一页。
    func show(replacing frame: NSRect? = nil, page: PanelPage? = nil, returnsToOverview: Bool = true) {
        let isOpen = panel.isVisible || panel.isMiniaturized
        if !isOpen {
            content.route = .home
        }
        // 开着弹出的表单时页面原样不动。
        let hasSheet = isOpen && panel.attachedSheet != nil
        if let page {
            if !isOpen {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { push(page) }
            } else if !hasSheet {
                push(page)
            }
        } else if isOpen, !hasSheet, returnsToOverview {
            pop()
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
        // 关窗只是收起 (不释放)，这时遮挡状态还没变，先记成看不见，提示条马上停。
        content.isWindowVisible = false
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

    /// Esc 的兜底 (平时由页头的返回、表单的「算了」这些按钮接走，按钮没接到时才走到这里)，每次只退一级：
    /// 页面里有下一级 (历史的月日历、单日详情) 先退那一级，否则从页面退回概览；概览上开着扣钱、请假表单时回到概览。
    /// 返回 false 表示已经在概览上，没什么可退的，由窗口关掉自己。
    private func handleCancel() -> Bool {
        if let page = content.page {
            if !goBackInside(page) { pop() }
            return true
        }
        if content.route != .home {
            content.route = .home
            return true
        }
        return false
    }

    /// 让页面自己退一级；页面已经在首页时返回 false。目标、设置没有下一级 (弹出的表单是挂在窗口上的 sheet，自己接 Esc)。
    private func goBackInside(_ page: PanelPage) -> Bool {
        switch page {
        case .history: pages.history.goBack()
        case .goals, .settings: false
        }
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

    /// 露出来时立即刷新并接着定时刷；看不见时 `scheduleNextRefresh` 不再排下一次，定时器自然停下。首页提示条跟着停、开 (`isWindowVisible`)。
    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateVisibility()
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

    /// 把窗口看不看得见交给面板；没变时不写，免得白白重算。
    private func updateVisibility() {
        let visible = panel.occlusionState.contains(.visible)
        if content.isWindowVisible != visible { content.isWindowVisible = visible }
    }

    private func refresh() {
        updateVisibility()
        let snap = model.currentSnapshot()
        content.panel = snap.panel
        content.status = snap.today?.status
        content.leaveForm = snap.leaveForm
        // 请假表单开着时没了 (如过了零点到了不上班的日子)，视图已经改画概览，路由也跟着回去，免得 Esc 白按一次、庆祝动画被挡住。
        if content.leaveForm == nil, case .leave = content.route {
            content.route = .home
        }
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
        // 标题栏 52 高 (`.tall`)，红绿灯在里面垂直居中：概览、原地的表单、推进来的页面都顶到窗口上沿，
        // 表单与页面的页头 (`PageHeader`，同高) 和红绿灯排成一行，概览在这一行放提示条 (`HomeLayout` 从窗口顶边算)。
        // 钉住按钮在标题栏右侧，和红绿灯同一行，画在概览那一层 (`togglePin`)：页面推进来时盖住它，退出去时再露出来。
        let view = TodayPanelView(
            content: content, actions: actions, navigation: navigation,
            page: { [weak self] page in self?.pageView(page) ?? AnyView(EmptyView()) },
            togglePin: { [weak self] in self?.togglePin() }
        )
        let panel = WindowChrome.makeWindow(PanelWindow.self, title: "今日概览", titlebar: .tall, rootView: view)
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.handleCancel() ?? false }
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

/// 今日概览窗口：按 Esc 先退一级 (平时由页头的返回、表单的「算了」接走，这里兜底，见 `handleCancel`)，在概览上再按才关窗。
private final class PanelWindow: NSWindow {
    /// 返回 true 表示已经退了一级，不关窗。
    var onCancel: () -> Bool = { false }

    override func cancelOperation(_ sender: Any?) {
        if !onCancel() { performClose(sender) }
    }
}
