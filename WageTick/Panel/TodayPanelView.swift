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
                LeaveFormView(
                    mode: mode, actions: actions, initialForm: content.leaveForm,
                    subtitle: content.panel?.dateText, dismiss: goHome
                )
            }
        }
        .frame(width: PanelMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
    }

    /// 概览：上面各段在窗口里滚动 (提示条多了时可能放不下)，情绪按钮与底部入口栏固定在窗口底部。
    private var home: some View {
        VStack(spacing: 0) {
            if let panel = content.panel {
                ScrollBody { homeSections(panel) }
                actionsSection(panel)
                PanelFooter(
                    bossHotkey: content.bossHotkey,
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

    private func homeSections(_ panel: TodayPanel) -> some View {
        VStack(spacing: 0) {
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
            GoalCardView(
                card: panel.goal,
                queue: panel.goalQueue,
                countText: panel.goalCountText,
                openGoals: navigation.openGoals
            )
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
            notice: attendance.notice
        )
        progressZone {
            if let progress = attendance.progress {
                PanelProgress(progress: progress)
            } else {
                unpaidWorkButton(button)
            }
        }
        // 扣款只在统计行里显示合计，明细在历史的单日详情里看和改。
        PanelStatsRow(stats: attendance.stats)
    }

    /// 白干计时中：与上班中同样的结构，主数字为今日已倒贴，进度区换成「终于下班了」(F4 第 4 条)。
    @ViewBuilder
    private func unpaidWorkSection(_ unpaidWork: UnpaidWorkPanel, button: UnpaidWorkButton?) -> some View {
        PanelHero(
            label: "今日已倒贴",
            headline: unpaidWork.headline,
            caption: unpaidWork.caption
        )
        progressZone { unpaidWorkButton(button) }
        PanelStatsRow(stats: unpaidWork.stats)
    }

    /// 休息日 (设计稿 P2 休息日 · 760)：居中的小牛 120、「今天休息」30/700，下面两行说明与下一个上班日；统计行为本月已上班、本月累计。
    @ViewBuilder
    private func restSection(_ rest: RestPanel) -> some View {
        VStack(spacing: Spacing.s16) {
            Image(.cowMascot)
                .resizable()
                .scaledToFit()
                .frame(width: Self.mascotSize, height: Self.mascotSize)
                .accessibilityHidden(true)
            VStack(spacing: Spacing.s6) {
                Text(rest.headline).font(AppFont.ui(30, .bold)).foregroundStyle(Palette.ink)
                ForEach([rest.tagline, rest.nextAttendanceText].compactMap { $0 }, id: \.self) { line in
                    Text(line).font(AppFont.body).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 34, leading: Spacing.screen, bottom: 30, trailing: Spacing.screen))
        PanelStatsRow(stats: rest.stats)
    }

    /// 休息日小牛的边长 (设计稿 Mascot 120×120)。
    private static let mascotSize: CGFloat = 120

    /// 进度区与白干按钮区 (设计稿 Progress、Action Zone)：左右 20、下边距 24。两者高度按各自内容，不再强求一致。
    private func progressZone(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(EdgeInsets(top: 0, leading: Spacing.screen, bottom: Spacing.s24, trailing: Spacing.screen))
    }

    /// 进度区位置上的白干计时按钮 (我还没走、终于下班了)：主按钮高 48、文字 14、图标 16。文案和命令都取自快照，原样发出。
    /// 不可用时 (已过 23:59:59) 留出同高的空位。
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
        } else {
            Color.clear.frame(height: PanelMetrics.unpaidWorkButtonHeight)
        }
    }

    /// 停止计时用奔跑的小人 (设计稿)，开始计时 (我还没走、被迫营业) 用公文包。
    private static func icon(for button: UnpaidWorkButton) -> Phosphor {
        button.command == .stopUnpaidWork ? .personSimpleRun : .briefcase
    }

    // MARK: 情绪按钮

    /// 情绪按钮区 (设计稿 Actions)：固定在入口栏上方，上边一条分隔线，内边距 16 / 20 / 18；按钮高 44、间距 10。
    /// 今天已请假时按钮上面多一行描述与「修改」。都没有时 (如休息日被迫营业中) 整段不显示。
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
                    HStack(spacing: Spacing.s10) {
                        ForEach(buttons, content: moodButton)
                    }
                }
            }
            .padding(EdgeInsets(top: Spacing.s16, leading: Spacing.screen, bottom: Spacing.s18, trailing: Spacing.screen))
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
        .buttonStyle(.secondary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
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
