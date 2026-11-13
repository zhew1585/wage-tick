import OSLog
import SwiftUI
import WageCore

/// 面板底部入口栏要打开的窗口。
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

/// 今日概览面板 (PRD F4，设计稿 P2 · 760)。所有文字和数字原样取自快照的 `TodayPanel`，这里只管排版。
/// 从上到下：日期与状态、主数字、进度区 (已下班、白干中换成白干计时按钮)、统计行、攒钱队列、情绪按钮、底部入口栏。
/// 窗口固定尺寸：情绪按钮与底部入口栏固定在窗口底部，上面各段放不下时滚动。
/// 白干计时按钮 (我还没走、被迫营业、终于下班了) 原样发出快照给的命令。
struct TodayPanelView: View {
    let content: TodayPanelContent
    let actions: PanelActions
    let navigation: PanelNavigation

    var body: some View {
        Group {
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
        .frame(width: PanelMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
    }

    /// 概览 (设计稿「大胆风格」)：头图与进度格、统计行、攒钱队列一起放进滚动区，放不下时往下滑，头图收成窄栏钉在顶上；
    /// 底部按钮与入口栏固定在窗口底部。
    private var home: some View {
        VStack(spacing: 0) {
            if let panel = content.panel {
                HeroScroll { collapse in
                    PanelHomeHero(panel: panel, collapse: collapse)
                } content: {
                    homeSections(panel)
                }
                actionsSection(panel)
                PanelFooter(
                    payday: panel.payday,
                    openHistory: navigation.openHistory,
                    openGoals: navigation.openGoals,
                    openSettings: navigation.openSettings
                )
            }
        }
        // 盖在面板上，不改变面板布局 (AC-HOME-11)。
        .overlay {
            if let celebration = content.celebration {
                CelebrationView(celebration: celebration) { content.celebration = nil }
            }
        }
    }

    /// 头图下面：提示条、进度格 (休息日没在白干时没有)、扣款超过日薪的提示、统计行、攒钱队列。
    private func homeSections(_ panel: TodayPanel) -> some View {
        VStack(spacing: Spacing.s18) {
            notices(panel.notices)
            if let blocks = panel.blocks {
                HourBlocksView(blocks: blocks)
            }
            if case .attendance(let attendance) = panel.body, let notice = attendance.notice {
                Text(notice).font(AppFont.caption).foregroundStyle(Palette.accent).frame(maxWidth: .infinity, alignment: .leading)
            }
            BoldStatsRow(stats: Self.stats(panel.body))
            GoalCardView(
                card: panel.goal,
                queue: panel.goalQueue,
                countText: panel.goalCountText,
                density: .full,
                openGoals: navigation.openGoals
            )
        }
        .padding(EdgeInsets(top: Spacing.s20, leading: Spacing.screen, bottom: Spacing.s16, trailing: Spacing.screen))
    }

    private static func stats(_ body: TodayPanel.Body) -> [StatItem] {
        switch body {
        case .attendance(let attendance): attendance.stats
        case .rest(let rest): rest.stats
        case .unpaidWork(let unpaidWork): unpaidWork.stats
        }
    }

    private func goHome() {
        content.route = .home
    }

    /// 面板顶部提示条 (AC-HOME-08、AC-HOME-09)，没有时不占位。
    @ViewBuilder
    private func notices(_ notices: [String]) -> some View {
        if !notices.isEmpty {
            VStack(spacing: Spacing.s6) {
                ForEach(notices, id: \.self, content: PanelNoticeBanner.init(text:))
            }
        }
    }

    /// 停止计时用奔跑的小人 (设计稿)，开始计时 (我还没走、被迫营业) 用公文包。
    private static func icon(for button: UnpaidWorkButton) -> Phosphor {
        button.command == .stopUnpaidWork ? .personSimpleRun : .briefcase
    }

    // MARK: 情绪按钮

    /// 底部按钮区 (设计稿「大胆风格」Actions)：固定在入口栏上方，胶囊按钮高 46、间距 10，内边距 12 / 20 / 14。
    /// 今天已请假时按钮上面多一行描述与「修改」。都没有时整段不显示。
    @ViewBuilder
    private func actionsSection(_ panel: TodayPanel) -> some View {
        let buttons = moodButtons(panel)
        let leave = currentLeave
        if !buttons.isEmpty || leave != nil {
            VStack(spacing: Spacing.s10) {
                if let leave {
                    currentLeaveRow(leave.current, text: leave.text)
                }
                if !buttons.isEmpty {
                    HStack(spacing: Spacing.s10) {
                        ForEach(buttons, content: moodButton)
                    }
                }
            }
            .padding(EdgeInsets(top: Spacing.s12, leading: Spacing.screen, bottom: Spacing.s14, trailing: Spacing.screen))
        }
    }

    /// 底部按钮 (设计稿「大胆风格」)：上班日为「今天扣钱了」+「请假」，已下班把请假换成「我还没走」，白干中换成「终于下班了」；
    /// 休息日只有「被迫营业」，休息日白干中只有「终于下班了」。
    /// 「今天扣钱了」只在快照给出入口时出现 (AC-FINE-07)；请假入口与能否新请由核心决定 (PRD 4.3.5 #8)；
    /// 白干计时按钮 (F7) 的文案与可用与否取自快照。
    private func moodButtons(_ panel: TodayPanel) -> [MoodButton] {
        var buttons: [MoodButton] = []
        switch panel.body {
        case .rest:
            break
        case .unpaidWork(let unpaidWork) where unpaidWork.isRestDay:
            break
        case .attendance, .unpaidWork:
            if panel.deductionEntry != nil {
                buttons.append(.deduction)
            }
        }
        if let button = panel.unpaidWorkButton {
            buttons.append(.unpaidWork(button))
        } else if content.leaveForm?.canRequest == true {
            buttons.append(.leave)
        }
        return buttons
    }

    /// 胶囊按钮：扣钱是描边，请假、我还没走、被迫营业是墨色实心，终于下班了是品牌橙实心。
    @ViewBuilder
    private func moodButton(_ button: MoodButton) -> some View {
        switch button {
        case .deduction:
            Button { content.route = .deduction(.add) } label: {
                Label { Text("今天扣钱了") } icon: { PhosphorIcon(.trendDown) }
            }
            .buttonStyle(.pill(.outline))
        case .leave:
            Button { content.route = .leave(.request) } label: {
                Label { Text("请假") } icon: { PhosphorIcon(.umbrella) }
            }
            .buttonStyle(.pill(.ink))
        case .unpaidWork(let unpaidWork):
            Button { send(unpaidWork.command) } label: {
                Label { Text(unpaidWork.title) } icon: { PhosphorIcon(Self.icon(for: unpaidWork)) }
            }
            .buttonStyle(.pill(unpaidWork.command == .stopUnpaidWork ? .accent : .ink))
        }
    }

    /// 今天已有的请假与描述；没请假时为 nil。
    private var currentLeave: (current: Leave, text: String)? {
        guard let form = content.leaveForm, let current = form.current, let text = form.currentText else { return nil }
        return (current, text)
    }

    /// 今天已请假时一句描述和「修改」入口，撤销在修改表单里 (F6)。
    private func currentLeaveRow(_ leave: Leave, text: String) -> some View {
        HStack(spacing: Spacing.s6) {
            PhosphorIcon(.umbrella, size: 13).foregroundStyle(Palette.muted)
            Text(text).font(AppFont.caption).foregroundStyle(Palette.muted)
            Spacer()
            Button { content.route = .leave(.edit(leave)) } label: {
                Text("修改")
                    .font(AppFont.label)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Spacing.s8)
                    .padding(.vertical, 3)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.highlight(radius: Radius.r6))
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

/// 情绪按钮行里的一个按钮。
private enum MoodButton: Identifiable {
    case deduction
    case leave
    /// 休息日的被迫营业。
    case unpaidWork(UnpaidWorkButton)

    var id: String {
        switch self {
        case .deduction: "deduction"
        case .leave: "leave"
        case .unpaidWork: "unpaidWork"
        }
    }
}
