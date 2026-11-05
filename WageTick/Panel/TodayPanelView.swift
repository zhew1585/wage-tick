import OSLog
import SwiftUI
import WageCore

/// 今日概览面板 (PRD F4)。所有文字和数字原样取自快照的 `TodayPanel`，这里只管排版。
/// 目标区、请假与被迫营业按钮、「我还没走」按钮只占位，功能留给后续票。
struct TodayPanelView: View {
    let content: TodayPanelContent
    let actions: PanelActions

    @State private var deductionForm: DeductionFormRequest?

    /// 进度区高度：已下班时换成「我还没走」按钮，高度保持一致 (AC-HOME-11)。
    private static let progressAreaHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let panel = content.panel {
                header(panel)
                switch panel.body {
                case .attendance(let attendance):
                    attendanceSection(attendance)
                case .rest(let rest):
                    restSection(rest)
                }
                goalPlaceholder
                Divider()
                moodButtons(panel)
            }
        }
        .padding(20)
        .frame(width: 340)
        .sheet(item: $deductionForm) { request in
            DeductionFormView(
                request: request,
                entry: content.panel?.deductionEntry,
                actions: actions,
                dismiss: { deductionForm = nil }
            )
        }
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
    private func attendanceSection(_ attendance: AttendancePanel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(attendance.headline)
                .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
            Text(attendance.caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let notice = attendance.notice {
                Text(notice).font(.callout).foregroundStyle(.orange)
            }
        }
        Group {
            if let progress = attendance.progress {
                progressSection(progress)
            } else {
                Button("我还没走") {}
                    .disabled(true)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.progressAreaHeight)
        statsRow(attendance.stats)
        if !attendance.deductions.isEmpty {
            deductionList(attendance.deductions)
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

    /// 目标区占位 (F9，后续票)。
    private var goalPlaceholder: some View {
        Text("目标")
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 情绪按钮：应出勤日为扣钱、请假，休息日为被迫营业 (F4)。
    /// 「今天扣钱了」只在快照给出入口时出现 (AC-FINE-07)；请假 (F6)、被迫营业 (F7) 留给后续票，先占位。
    private func moodButtons(_ panel: TodayPanel) -> some View {
        HStack {
            if panel.body.isRest {
                Button("被迫营业") {}.disabled(true)
            } else {
                if panel.deductionEntry != nil {
                    Button("今天扣钱了") { deductionForm = .add }
                }
                Button("请假") {}.disabled(true)
            }
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

private extension TodayPanel.Body {
    var isRest: Bool {
        if case .rest = self { true } else { false }
    }
}
