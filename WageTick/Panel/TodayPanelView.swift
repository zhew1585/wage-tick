import SwiftUI
import WageCore

/// 今日概览面板 (PRD F4)。所有文字和数字原样取自快照的 `TodayPanel`，这里只管排版。
/// 白干计时按钮原样发出快照给的命令；目标区、扣钱与请假按钮本期只占位，功能留给后续票。
struct TodayPanelView: View {
    let content: TodayPanelContent

    /// 进度区高度：已下班时换成「我还没走」按钮、白干中换成「终于下班了」按钮，高度保持一致 (AC-HOME-11)。
    private static let progressAreaHeight: CGFloat = 44
    /// 情绪按钮行高度：白干中这一行可能没有按钮，固定高度让面板总高度不变 (AC-HOME-11)。
    private static let moodRowHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let panel = content.panel {
                header(panel)
                switch panel.body {
                case .attendance(let attendance):
                    attendanceSection(attendance, button: panel.unpaidWorkButton)
                case .rest(let rest):
                    restSection(rest)
                case .unpaidWork(let unpaidWork):
                    unpaidWorkSection(unpaidWork, button: panel.unpaidWorkButton)
                }
                goalPlaceholder
                Divider()
                moodButtons(panel)
            }
        }
        .padding(20)
        .frame(width: 340)
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
        headline(attendance.headline, caption: attendance.caption)
        Group {
            if let progress = attendance.progress {
                progressSection(progress)
            } else if let button {
                unpaidWorkButton(button)
            } else {
                Color.clear
            }
        }
        .frame(height: Self.progressAreaHeight)
        statsRow(attendance.stats)
    }

    /// 白干计时中：与上班中同样的结构，进度区换成「终于下班了」按钮 (F4 第 4 条)。
    @ViewBuilder
    private func unpaidWorkSection(_ unpaidWork: UnpaidWorkPanel, button: UnpaidWorkButton?) -> some View {
        headline(unpaidWork.headline, caption: unpaidWork.caption)
        Group {
            if let button {
                unpaidWorkButton(button)
            } else {
                Color.clear
            }
        }
        .frame(height: Self.progressAreaHeight)
        statsRow(unpaidWork.stats)
    }

    private func headline(_ headline: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
    }

    /// 白干计时按钮：文案和命令都取自快照，原样发出。
    private func unpaidWorkButton(_ button: UnpaidWorkButton) -> some View {
        Button {
            content.send(button.command)
        } label: {
            Text(button.title).frame(maxWidth: .infinity)
        }
        .controlSize(.large)
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

    /// 情绪按钮：应出勤日为扣钱、请假 (F5、F6，后续票，先占位)；休息日为被迫营业 (F7)。
    /// 白干计时中「终于下班了」在进度区，这一行留空。
    @ViewBuilder
    private func moodButtons(_ panel: TodayPanel) -> some View {
        HStack {
            switch panel.body {
            case .attendance:
                Group {
                    Button("今天扣钱了") {}
                    Button("请假") {}
                }
                .disabled(true)
            case .rest:
                if let button = panel.unpaidWorkButton {
                    Button(button.title) { content.send(button.command) }
                }
            case .unpaidWork:
                EmptyView()
            }
        }
        .frame(height: Self.moodRowHeight)
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
