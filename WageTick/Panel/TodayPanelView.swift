import OSLog
import SwiftUI
import WageCore

/// 今日概览面板 (PRD F4)。所有文字和数字原样取自快照的 `TodayPanel`，这里只管排版。
/// 白干计时按钮 (我还没走、被迫营业、终于下班了) 原样发出快照给的命令。
struct TodayPanelView: View {
    let content: TodayPanelContent
    let actions: PanelActions
    /// 点击空的目标区时打开目标管理 (F9)。
    let openGoals: () -> Void

    @State private var deductionForm: DeductionFormRequest?
    /// 正在弹出的请假表单；nil 时没有表单。
    @State private var leaveForm: LeaveFormView.Mode?

    /// 进度区高度：已下班时换成「我还没走」按钮、白干中换成「终于下班了」按钮，高度保持一致 (AC-HOME-11)。
    private static let progressAreaHeight: CGFloat = 44
    /// 情绪按钮行高度：白干中这一行可能没有按钮，固定高度让面板总高度不变 (AC-HOME-11)。
    private static let moodRowHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let panel = content.panel {
                ForEach(panel.notices, id: \.self, content: noticeBanner)
                header(panel)
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
                    openGoals: openGoals,
                    toggleQueue: { send(.toggleGoalQueueExpanded) }
                )
                Divider()
                currentLeaveRow
                moodButtons(panel)
            }
        }
        .padding(20)
        .frame(width: 340)
        // 盖在面板上，不改变面板高度 (AC-HOME-11)。
        .overlay {
            if let celebration = content.celebration {
                CelebrationView(celebration: celebration) { content.celebration = nil }
            }
        }
        .sheet(item: $deductionForm) { request in
            DeductionFormView(
                request: request,
                entry: content.panel?.deductionEntry,
                actions: actions,
                dismiss: { deductionForm = nil }
            )
        }
    }

    /// 面板顶部提示条，如节假日数据缺失 (AC-HOME-08)。文案原样取自快照。
    private func noticeBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func header(_ panel: TodayPanel) -> some View {
        HStack {
            Text(panel.dateText)
            Text(panel.timeText).monospacedDigit()
            Spacer()
            Text(panel.statusLabel)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func attendanceSection(_ attendance: AttendancePanel, button: UnpaidWorkButton?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            headline(attendance.headline, caption: attendance.caption)
            if let notice = attendance.notice {
                Text(notice).font(.callout).foregroundStyle(.orange)
            }
        }
        Group {
            if let progress = attendance.progress {
                progressSection(progress)
            } else {
                unpaidWorkArea(button)
            }
        }
        .frame(height: Self.progressAreaHeight)
        statsRow(attendance.stats)
        if !attendance.deductions.isEmpty {
            deductionList(attendance.deductions)
        }
    }

    /// 白干计时中：与上班中同样的结构，进度区换成「终于下班了」按钮 (F4 第 4 条)。
    @ViewBuilder
    private func unpaidWorkSection(_ unpaidWork: UnpaidWorkPanel, button: UnpaidWorkButton?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            headline(unpaidWork.headline, caption: unpaidWork.caption)
        }
        unpaidWorkArea(button)
            .frame(height: Self.progressAreaHeight)
        statsRow(unpaidWork.stats)
    }

    /// 主数字与下方一行小字。
    @ViewBuilder
    private func headline(_ headline: String, caption: String) -> some View {
        Text(headline)
            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
        Text(caption)
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            // 固定单行，上班中与白干中的面板总高度一致 (AC-HOME-11)。
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// 进度区位置上的白干计时按钮 (我还没走、终于下班了)：文案和命令都取自快照，原样发出。不可用时留空占位。
    @ViewBuilder
    private func unpaidWorkArea(_ button: UnpaidWorkButton?) -> some View {
        if let button {
            Button {
                send(button.command)
            } label: {
                Text(button.title).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        } else {
            Color.clear
        }
    }

    /// 今天的扣钱明细，每笔可编辑、删除 (AC-FINE-04、PRD 4.4.1 #1)。
    private func deductionList(_ items: [DeductionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                        if let detail = item.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(item.amount).monospacedDigit()
                    Button { deductionForm = .edit(item) } label: { Image(systemName: "pencil") }
                        .help("编辑")
                    Button { send(.deleteDeduction(id: item.id)) } label: { Image(systemName: "trash") }
                        .help("删除")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }
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

    @ViewBuilder
    private func restSection(_ rest: RestPanel) -> some View {
        Text(rest.headline).font(.system(size: 28, weight: .semibold, design: .rounded))
        statsRow(rest.stats)
    }

    private func progressSection(_ progress: WorkProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progress.label)
                Spacer()
                Text(progress.percent)
            }
            .font(.callout)
            .monospacedDigit()
            SegmentedProgressBar(segments: progress.segments)
        }
    }

    private func statsRow(_ stats: [StatItem]) -> some View {
        HStack(alignment: .top) {
            ForEach(stats, id: \.title) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.caption).foregroundStyle(.secondary)
                    Text(item.value).font(.body.weight(.medium)).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 今天已请假时显示一句描述和「修改」入口，撤销在修改表单里 (F6)。
    @ViewBuilder
    private var currentLeaveRow: some View {
        if let form = content.leaveForm, let current = form.current, let text = form.currentText {
            HStack {
                Text(text).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("修改") { leaveForm = .edit(current) }
            }
        }
    }

    /// 情绪按钮：应出勤日为扣钱、请假，休息日为被迫营业 (F4)。
    /// 「今天扣钱了」只在快照给出入口时出现 (AC-FINE-07)；请假入口与能否新请由核心决定 (PRD 4.3.5 #8)；
    /// 被迫营业 (F7) 的文案与可用与否取自快照；被迫营业计时中「终于下班了」在进度区，这一行不再放它。
    private func moodButtons(_ panel: TodayPanel) -> some View {
        HStack {
            switch panel.body {
            case .rest:
                if let button = panel.unpaidWorkButton {
                    Button(button.title) { send(button.command) }
                }
            case .unpaidWork(let unpaidWork) where unpaidWork.isRestDay:
                EmptyView()
            case .attendance, .unpaidWork:
                if panel.deductionEntry != nil {
                    Button("今天扣钱了") { deductionForm = .add }
                }
            }
            if content.leaveForm?.canRequest == true {
                Button("请假") { leaveForm = .request }
            }
        }
        .frame(height: Self.moodRowHeight)
        // 与扣钱表单分开挂，避免同一视图上挂两个 sheet。
        .sheet(item: $leaveForm) { mode in
            LeaveFormView(mode: mode, actions: actions, dismiss: { leaveForm = nil })
        }
    }
}

/// 分段进度条：每段宽度按 `share` 分配，段与段之间留出间隔表示午休。
private struct SegmentedProgressBar: View {
    let segments: [ProgressSegment]
    private let gap: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let usable = max(0, geometry.size.width - gap * CGFloat(segments.count - 1))
            HStack(spacing: gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    let width = usable * segment.share
                    Capsule()
                        .fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.tint).frame(width: width * segment.filled)
                        }
                        .frame(width: width)
                }
            }
        }
        .frame(height: 8)
    }
}
