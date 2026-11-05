import SwiftUI
import WageCore

/// 今日概览面板 (PRD F4)。所有文字和数字原样取自快照的 `TodayPanel`，这里只管排版。
/// 目标区、「今天扣钱了」「被迫营业」「我还没走」按钮本期只占位，功能留给后续票。
struct TodayPanelView: View {
    let content: TodayPanelContent
    /// 情绪按钮的表单通过它发命令、试算。
    let model: AppModel
    /// 表单保存后立即刷新面板，不等下一次定时刷新。
    let onStateChanged: () -> Void

    /// 正在弹出的请假表单；nil 时没有表单。
    @State private var leaveMode: LeaveFormView.Mode?

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
                currentLeaveRow
                moodButtons(isRestDay: panel.body.isRest)
            }
        }
        .padding(20)
        .frame(width: 340)
        .sheet(item: $leaveMode) { mode in
            LeaveFormView(
                model: model,
                mode: mode,
                onSaved: {
                    leaveMode = nil
                    onStateChanged()
                },
                onCancel: { leaveMode = nil }
            )
        }
    }

    /// 今天已请假时显示一句描述和「修改」入口，撤销在修改表单里。
    @ViewBuilder
    private var currentLeaveRow: some View {
        if let form = content.leaveForm, let current = form.current, let text = form.currentText {
            HStack {
                Text(text).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("修改") { leaveMode = .edit(current) }
            }
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
    }

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

    /// 情绪按钮：应出勤日为扣钱、请假，休息日为被迫营业 (F5、F7 本期占位)。
    /// 请假入口只在今天应出勤时出现 (PRD 4.3.5 #8)；能否新请由核心决定。
    private func moodButtons(isRestDay: Bool) -> some View {
        HStack {
            if isRestDay {
                Button("被迫营业") {}.disabled(true)
            } else {
                Button("今天扣钱了") {}.disabled(true)
            }
            if content.leaveForm?.canRequest == true {
                Button("请假") { leaveMode = .request }
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
