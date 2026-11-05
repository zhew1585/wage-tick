import SwiftUI
import WageCore

/// 今日概览面板 (PRD F4)。所有文字和数字原样取自快照的 `TodayPanel`，这里只管排版。
/// 目标区、情绪按钮、「我还没走」按钮本期只占位，功能留给后续票。
struct TodayPanelView: View {
    let content: TodayPanelContent

    /// 进度区高度：已下班时换成「我还没走」按钮，高度保持一致 (AC-HOME-11)。
    private static let progressAreaHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let panel = content.panel {
                ForEach(panel.notices, id: \.self, content: noticeBanner)
                header(panel)
                switch panel.body {
                case .attendance(let attendance):
                    attendanceSection(attendance)
                case .rest(let rest):
                    restSection(rest)
                }
                goalPlaceholder
                Divider()
                moodButtons(isRestDay: panel.body.isRest)
            }
        }
        .padding(20)
        .frame(width: 340)
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

    /// 情绪按钮占位 (F5、F6、F7，后续票)：应出勤日为扣钱、请假，休息日为被迫营业。
    private func moodButtons(isRestDay: Bool) -> some View {
        HStack {
            if isRestDay {
                Button("被迫营业") {}
            } else {
                Button("今天扣钱了") {}
                Button("请假") {}
            }
        }
        .disabled(true)
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
