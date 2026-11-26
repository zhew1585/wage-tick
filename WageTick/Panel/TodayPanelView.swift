import OSLog
import SwiftUI
import WageCore

/// 面板底部入口栏要推进来的页面。
struct PanelNavigation {
    let openHistory: () -> Void
    let openGoals: () -> Void
    let openSettings: () -> Void
}

/// 面板里正在显示的页面：概览，或原地打开的扣钱、请假表单 (设计稿 F5、F6 的返回箭头回到概览)。
enum PanelRoute: Equatable {
    case home
    case deduction(DeductionFormRequest)
    case leave(LeaveFormView.Mode)
}

/// 今日概览面板 (PRD F4，首页改版定稿)。所有文字和数字原样取自快照的 `TodayPanel`，这里只管排版。
/// 从窗口顶边起按 `HomeLayout` 的七个区域摆放：日期与状态、主数字、进度区 (已下班、白干中换成白干计时按钮)、统计卡、攒钱队列、情绪按钮、入口栏。
/// 各区域在所有状态下位置、高度都一样，换状态只换区域里的内容；提示条在红绿灯那一行 (`HomeNoticeLayout`)，不推开下面的内容。
/// 白干计时按钮 (我还没走、被迫营业、终于下班了) 原样发出快照给的命令。
struct TodayPanelView: View {
    let content: TodayPanelContent
    let actions: PanelActions
    let navigation: PanelNavigation
    /// 推进来的页面 (历史、目标、设置) 的视图。
    let page: (PanelPage) -> AnyView
    /// 切换钉住；给了就在标题栏右侧画钉住按钮 (窗口里用)，预览不给。
    var togglePin: (() -> Void)?

    /// 概览 (或原地打开的扣钱、请假表单) 在底下，历史、目标、设置从右边滑进来盖在上面 (`pushed`)。
    /// 概览、表单、推进来的页面都顶到窗口上沿，各自把红绿灯那一行排进去 (概览放提示条，表单与页面放页头)。
    /// 有页面盖着时底下整个停用：点不到、Tab 聚焦不到、辅助功能读不到，按键只归上面的页面。
    /// 钉住按钮、提示条跟概览在同一层，页面滑进滑出时被页面盖住、露出，不会叠在页头上。
    var body: some View {
        ZStack {
            base
                .environment(\.formSheetPlacement, .window)
                .overlay(alignment: .topLeading) {
                    if content.route == .home, let panel = content.panel {
                        noticeBanner(panel)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let togglePin {
                        PinButton(content: content, toggle: togglePin)
                            .frame(height: WindowChrome.Titlebar.tall.height)
                            .padding(.trailing, Spacing.s12)
                    }
                }
                .disabled(content.page != nil)
                .accessibilityHidden(content.page != nil)
            if let current = content.page {
                page(current)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Palette.bg)
                    .pushed(level: 1)
            }
        }
        .animation(.push, value: content.page)
        .frame(width: PanelMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
    }

    /// 概览，或原地替换概览的扣钱、请假表单。
    @ViewBuilder
    private var base: some View {
        switch content.route {
        case .home:
            home
        case .deduction(let request):
            DeductionFormView(
                request: request, entry: content.panel?.deductionEntry, actions: actions,
                subtitle: content.panel?.dateText, dismiss: goHome
            )
        case .leave(let mode):
            // 请假入口只在有请假表单时出现；表单在打开期间消失 (如过了零点) 时回到概览。
            if let form = content.leaveForm {
                LeaveFormView(mode: mode, form: form, actions: actions, subtitle: content.panel?.dateText, dismiss: goHome)
            } else {
                home
            }
        }
    }

    /// 概览：七个区域各自按 `HomeLayout` 的上沿与高度定死，内容多少都不挪位置、不变高。
    /// 休息日 (不在白干计时) 主数字区与进度区合成一整块放小牛与「今天休息」。
    private var home: some View {
        ZStack(alignment: .top) {
            if let panel = content.panel {
                PanelTopBar(panel: panel).homeBand(HomeLayout.topBar)
                switch panel.body {
                case .attendance(let attendance):
                    PanelHero(
                        label: content.status == .offWork ? "今日结算" : "今日已赚",
                        headline: attendance.headline,
                        caption: attendance.caption
                    )
                    .homeBand(HomeLayout.hero)
                    Group {
                        if let progress = attendance.progress {
                            PanelProgress(progress: progress)
                        } else {
                            unpaidWorkButton(panel.unpaidWorkButton)
                        }
                    }
                    .homeBand(HomeLayout.progress)
                case .rest(let rest):
                    PanelRestHero(rest: rest).homeBand(HomeLayout.Band(top: HomeLayout.hero.top, height: HomeLayout.progress.bottom - HomeLayout.hero.top))
                case .unpaidWork(let unpaidWork):
                    PanelHero(label: unpaidWork.label, headline: unpaidWork.headline, caption: unpaidWork.caption, tone: Palette.loss)
                        .homeBand(HomeLayout.hero)
                    unpaidWorkButton(panel.unpaidWorkButton).homeBand(HomeLayout.progress)
                }
                // 扣款只在统计卡里显示合计，明细在历史的单日详情里看和改。
                PanelStatsCard(stats: Self.stats(panel)).homeBand(HomeLayout.stats)
                GoalCardView(card: panel.goal, queue: panel.goalQueue, openGoals: navigation.openGoals)
                    .homeBand(HomeLayout.goals)
                actionsSection(panel).homeBand(HomeLayout.actions)
                PanelFooter(
                    payday: panel.payday,
                    openHistory: navigation.openHistory,
                    openGoals: navigation.openGoals,
                    openSettings: navigation.openSettings
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surface)
                .homeBand(HomeLayout.footer, inset: 0)
            }
        }
        .frame(width: PanelMetrics.width, height: WindowMetrics.size.height, alignment: .top)
        // 盖满整个窗口，不改变面板布局 (AC-HOME-11)。
        .overlay {
            if let celebration = content.celebration {
                CelebrationView(celebration: celebration) { content.celebration = nil }
            }
        }
    }

    /// 三种主体各自的统计项。
    private static func stats(_ panel: TodayPanel) -> [StatItem] {
        switch panel.body {
        case .attendance(let attendance): attendance.stats
        case .rest(let rest): rest.stats
        case .unpaidWork(let unpaidWork): unpaidWork.stats
        }
    }

    private func goHome() {
        content.route = .home
    }

    /// 红绿灯那一行的提示条：依次是快照的提示 (AC-HOME-08、AC-HOME-09) 和扣款超过日薪的提示 (PRD 4.3.5 #6)；一条都没有时不显示。
    @ViewBuilder
    private func noticeBanner(_ panel: TodayPanel) -> some View {
        let notices = Self.notices(panel)
        if !notices.isEmpty {
            let frame = HomeNoticeLayout.frame
            PanelNoticeBanner(texts: notices)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
    }

    private static func notices(_ panel: TodayPanel) -> [String] {
        guard case .attendance(let attendance) = panel.body, let notice = attendance.notice else { return panel.notices }
        return panel.notices + [notice]
    }

    /// 进度区位置上的白干计时按钮 (我还没走、终于下班了)：主按钮 320×48、文字 14、图标 16，在进度区里上下各留 4。
    /// 文案和命令都取自快照，原样发出；不可用时留空 (正常用不到：已下班且没在计时时总能开始)。
    @ViewBuilder
    private func unpaidWorkButton(_ button: UnpaidWorkButton?) -> some View {
        if let button {
            Button { send(button.command) } label: {
                HStack(spacing: Spacing.s6) {
                    PhosphorIcon(Self.icon(for: button), size: 16)
                    Text(button.title).font(AppFont.ui(14, .semibold))
                }
            }
            .buttonStyle(.primary(fullWidth: true, height: PanelMetrics.unpaidWorkButtonHeight))
            .frame(height: PanelMetrics.unpaidWorkButtonHeight)
        }
    }

    /// 停止计时用奔跑的小人 (设计稿)，开始计时 (我还没走、被迫营业) 用公文包。
    private static func icon(for button: UnpaidWorkButton) -> Phosphor {
        button.command == .stopUnpaidWork ? .personSimpleRun : .briefcase
    }

    // MARK: 情绪按钮

    /// 情绪按钮区：两颗时各占一半 (间距 10)，一颗时整宽，高 44。都没有时 (如休息日被迫营业中) 空着。
    private func actionsSection(_ panel: TodayPanel) -> some View {
        HStack(spacing: Spacing.s10) {
            ForEach(moodButtons(panel), content: moodButton)
        }
    }

    /// 情绪按钮：应出勤日为扣钱、请假，休息日为被迫营业 (F4)。
    /// 「今天扣钱了」只在快照给出入口时出现 (AC-FINE-07)；请假入口与能否新请由核心决定 (PRD 4.3.5 #8)；
    /// 今天已经请了假时请假那一颗换成「请假状态」，点了修改请假；
    /// 被迫营业 (F7) 的文案与可用与否取自快照；白干计时中「终于下班了」在进度区，这一行不再放它。
    private func moodButtons(_ panel: TodayPanel) -> [MoodButton] {
        var buttons: [MoodButton] = []
        switch panel.body {
        case .rest:
            if let button = panel.unpaidWorkButton {
                buttons.append(.unpaidWork(button))
            }
        case .unpaidWork(let unpaidWork) where unpaidWork.isRestDay:
            break
        case .attendance, .unpaidWork:
            if panel.deductionEntry != nil {
                buttons.append(.deduction)
            }
        }
        if let form = content.leaveForm, let current = form.current, let shortText = form.shortText {
            buttons.append(.leaveStatus(current, text: shortText, rate: form.deductionRateText))
        } else if content.leaveForm?.canRequest == true {
            buttons.append(.leave)
        }
        return buttons
    }

    @ViewBuilder
    private func moodButton(_ button: MoodButton) -> some View {
        switch button {
        case .deduction:
            Button { content.route = .deduction(.add) } label: {
                Label { Text("今天扣钱了") } icon: { PhosphorIcon(.trendDown).foregroundStyle(Palette.loss) }
            }
            .buttonStyle(.secondary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
        case .leave:
            Button { content.route = .leave(.request) } label: {
                Label { Text("请假") } icon: { PhosphorIcon(.umbrella) }
            }
            .buttonStyle(.secondary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
        case .leaveStatus(let leave, let text, let rate):
            Button { content.route = .leave(.edit(leave)) } label: {
                LeaveStatusLabel(text: text, rate: rate)
            }
            .buttonStyle(.secondary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
        case .unpaidWork(let unpaidWork):
            Button { send(unpaidWork.command) } label: {
                Label { Text(unpaidWork.title) } icon: { PhosphorIcon(Self.icon(for: unpaidWork)) }
            }
            .buttonStyle(.secondary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
        }
    }

    /// 面板上直接发出的命令 (如删除)。正常操作下不会失败，失败时只记日志，面板不变。
    private func send(_ command: Command) {
        do {
            try actions.send(command)
        } catch {
            Self.logger.error("面板命令失败：\(error.message, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: AppIdentity.bundleID, category: "TodayPanel")
}

/// 标题栏右侧的图钉：未钉住为空心 muted，钉住为实心 accent。跟概览、原地的表单在同一层，推进来的页面会盖住它。
private struct PinButton: View {
    let content: TodayPanelContent
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            PhosphorIcon(content.isPinned ? .pushPinFill : .pushPin, size: 14)
                .foregroundStyle(content.isPinned ? Palette.accent : Palette.muted)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: Radius.r4, outset: 2))
        .help(content.isPinned ? "取消钉住" : "钉住：窗口始终在最前")
        .accessibilityLabel(content.isPinned ? "取消钉住" : "钉住")
    }
}

/// 情绪按钮行里的一个按钮。
private enum MoodButton: Identifiable {
    case deduction
    case leave
    /// 今天已请假：请假描述 (如「请假 10:00–12:00」) 与扣薪比例，点了修改这条请假。
    case leaveStatus(Leave, text: String, rate: String?)
    /// 休息日的被迫营业。
    case unpaidWork(UnpaidWorkButton)

    var id: String {
        switch self {
        case .deduction: "deduction"
        case .leave, .leaveStatus: "leave"
        case .unpaidWork: "unpaidWork"
        }
    }
}

/// 「请假状态」按钮里的内容：伞 14 (accent)，右边两行左对齐，请假描述 12/500 ink、扣薪比例 11 muted。左右内边距 12。
private struct LeaveStatusLabel: View {
    let text: String
    let rate: String?

    var body: some View {
        HStack(spacing: Spacing.s8) {
            PhosphorIcon(.umbrella, size: 14).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(text).font(AppFont.label).foregroundStyle(Palette.ink)
                if let rate {
                    Text(rate).font(AppFont.small).foregroundStyle(Palette.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        // 按钮样式自带左右 14，这里收回 2，内容离按钮边 12。
        .padding(.horizontal, -Spacing.s2)
    }
}

extension View {
    /// 放进首页的一个区域：从窗口顶边往下 `band.top`，高 `band.height`，左右各让出 `inset` (默认页面内边距 20)。
    func homeBand(_ band: HomeLayout.Band, inset: CGFloat = Spacing.screen) -> some View {
        frame(maxWidth: .infinity)
            .frame(height: band.height)
            .padding(.horizontal, inset)
            .padding(.top, band.top)
    }
}
