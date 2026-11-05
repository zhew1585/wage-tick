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

/// 今日概览面板 (PRD F4，设计稿 P2)。所有文字和数字原样取自快照的 `TodayPanel`，这里只管排版。
/// 从上到下：日期与状态、主数字、进度区 (已下班、白干中换成白干计时按钮)、统计行、目标区、情绪按钮、底部入口栏。
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
                LeaveFormView(mode: mode, actions: actions, subtitle: content.panel?.dateText, dismiss: goHome)
            }
        }
        .frame(width: PanelMetrics.width)
        .background(Palette.bg)
    }

    private var home: some View {
        VStack(spacing: 0) {
            if let panel = content.panel {
                notices(panel.notices)
                PanelTopBar(panel: panel)
                switch panel.body {
                case .attendance(let attendance):
                    attendanceSection(attendance, button: panel.unpaidWorkButton)
                case .rest(let rest):
                    restSection(rest)
                case .unpaidWork(let unpaidWork):
                    unpaidWorkSection(unpaidWork, button: panel.unpaidWorkButton)
                }
                PanelDivider()
                GoalCardView(
                    card: panel.goal,
                    queue: panel.goalQueue,
                    openGoals: navigation.openGoals,
                    toggleQueue: { send(.toggleGoalQueueExpanded) }
                )
                actionsSection(panel)
                PanelFooter(
                    bossHotkey: content.bossHotkey,
                    openHistory: navigation.openHistory,
                    openGoals: navigation.openGoals,
                    openSettings: navigation.openSettings
                )
            }
        }
        // 盖在面板上，不改变面板高度 (AC-HOME-11)。
        .overlay {
            if let celebration = content.celebration {
                CelebrationView(celebration: celebration) { content.celebration = nil }
            }
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
            .padding(EdgeInsets(top: Spacing.s12, leading: Spacing.screen, bottom: 0, trailing: Spacing.screen))
        }
    }

    // MARK: 三种主体

    /// 应出勤日：主数字为今日已赚 (已下班为今日结算)，下面进度区，已下班时进度区换成「我还没走」。
    @ViewBuilder
    private func attendanceSection(_ attendance: AttendancePanel, button: UnpaidWorkButton?) -> some View {
        PanelHero(
            label: content.status == .offWork ? "今日结算" : "今日已赚",
            headline: attendance.headline,
            caption: attendance.caption,
            notice: attendance.notice,
            currencyColor: Palette.money
        )
        progressZone {
            if let progress = attendance.progress {
                PanelProgress(progress: progress)
            } else {
                unpaidWorkButton(button)
            }
        }
        PanelDivider()
        PanelStatsRow(stats: attendance.stats)
        if !attendance.deductions.isEmpty {
            PanelDivider()
            PanelDeductionList(
                items: attendance.deductions,
                edit: { content.route = .deduction(.edit($0)) },
                delete: { send(.deleteDeduction(id: $0.id)) }
            )
        }
    }

    /// 白干计时中：与上班中同样的结构，主数字为今日已倒贴，进度区换成「终于下班了」(F4 第 4 条)。
    @ViewBuilder
    private func unpaidWorkSection(_ unpaidWork: UnpaidWorkPanel, button: UnpaidWorkButton?) -> some View {
        PanelHero(
            label: "今日已倒贴",
            headline: unpaidWork.headline,
            caption: unpaidWork.caption,
            currencyColor: Palette.loss
        )
        progressZone { unpaidWorkButton(button) }
        PanelDivider()
        PanelStatsRow(stats: unpaidWork.stats)
    }

    /// 休息日 (设计稿 P2 休息日)：左边小牛，右边「今天休息」；统计行放前两项，其余 (下一个应出勤日) 放在标题下面。
    @ViewBuilder
    private func restSection(_ rest: RestPanel) -> some View {
        HStack(spacing: Spacing.s16) {
            Image(.cowMascot)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(rest.headline).font(AppFont.ui(24, .bold)).foregroundStyle(Palette.ink)
                ForEach(rest.stats.dropFirst(Self.restStatsInRow), id: \.title) { item in
                    Text("\(item.title) \(item.value)").font(AppFont.caption).foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 18, leading: Spacing.screen, bottom: 22, trailing: Spacing.screen))
        PanelDivider()
        PanelStatsRow(stats: Array(rest.stats.prefix(Self.restStatsInRow)))
    }

    /// 休息日统计行放几项 (设计稿：本月已上班、本月累计)。
    private static let restStatsInRow = 2

    /// 进度区与白干按钮区同高 (AC-HOME-11)：内容 37 + 下边距 18。
    private func progressZone(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(height: ThemeButtonStyle.height, alignment: .top)
            .padding(.horizontal, Spacing.screen)
            .padding(.bottom, PanelMetrics.progressZoneHeight - ThemeButtonStyle.height)
    }

    /// 进度区位置上的白干计时按钮 (我还没走、终于下班了)：文案和命令都取自快照，原样发出。不可用时留空占位。
    @ViewBuilder
    private func unpaidWorkButton(_ button: UnpaidWorkButton?) -> some View {
        if let button {
            Button { send(button.command) } label: {
                Label { Text(button.title) } icon: { PhosphorIcon(Self.icon(for: button)) }
            }
            .buttonStyle(.primary(fullWidth: true))
        } else {
            Color.clear
        }
    }

    /// 停止计时用奔跑的小人 (设计稿)，开始计时 (我还没走、被迫营业) 用公文包。
    private static func icon(for button: UnpaidWorkButton) -> Phosphor {
        button.command == .stopUnpaidWork ? .personSimpleRun : .briefcase
    }

    // MARK: 情绪按钮

    /// 情绪按钮区：今天已请假时上面一行描述与「修改」，下面情绪按钮。都没有时 (如休息日被迫营业中) 整段不显示。
    @ViewBuilder
    private func actionsSection(_ panel: TodayPanel) -> some View {
        let buttons = moodButtons(panel)
        let leave = currentLeave
        if !buttons.isEmpty || leave != nil {
            PanelDivider()
            VStack(spacing: Spacing.s10) {
                if let leave {
                    currentLeaveRow(leave.current, text: leave.text)
                }
                if !buttons.isEmpty {
                    HStack(spacing: Spacing.s8) {
                        ForEach(buttons, content: moodButton)
                    }
                }
            }
            .padding(EdgeInsets(top: Spacing.s14, leading: Spacing.screen, bottom: Spacing.s16, trailing: Spacing.screen))
        }
    }

    /// 情绪按钮：应出勤日为扣钱、请假，休息日为被迫营业 (F4)。
    /// 「今天扣钱了」只在快照给出入口时出现 (AC-FINE-07)；请假入口与能否新请由核心决定 (PRD 4.3.5 #8)；
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
        if content.leaveForm?.canRequest == true {
            buttons.append(.leave)
        }
        return buttons
    }

    private func moodButton(_ button: MoodButton) -> some View {
        Group {
            switch button {
            case .deduction:
                Button { content.route = .deduction(.add) } label: {
                    Label { Text("今天扣钱了") } icon: { PhosphorIcon(.trendDown).foregroundStyle(Palette.loss) }
                }
            case .leave:
                Button { content.route = .leave(.request) } label: {
                    Label { Text("请假") } icon: { PhosphorIcon(.umbrella) }
                }
            case .unpaidWork(let unpaidWork):
                Button { send(unpaidWork.command) } label: {
                    Label { Text(unpaidWork.title) } icon: { PhosphorIcon(Self.icon(for: unpaidWork)) }
                }
            }
        }
        .buttonStyle(.secondary(fullWidth: true))
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
            .buttonStyle(.plain)
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
