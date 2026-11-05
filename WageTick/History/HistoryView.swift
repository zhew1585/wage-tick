import SwiftUI
import WageCore

/// 历史 (PRD F10、F11)：月列表，点某月进月日历，日历里可编辑某天与该月月薪。所有文字取自快照，这里只管排版、导航与发命令。
struct HistoryView: View {
    let content: HistoryContent
    /// 单日编辑、改月薪发命令的口子 (#15)。
    let actions: PanelActions

    var body: some View {
        Group {
            if let snapshot = content.snapshot {
                if let month = content.selectedMonth.flatMap(snapshot.historyMonth) {
                    MonthCalendarView(month: month, actions: actions, back: { content.selectedMonth = nil })
                        // 换月时清掉上个月选中的那天。
                        .id(month.summary.month)
                } else {
                    MonthListView(months: snapshot.historyMonths(), open: { content.selectedMonth = $0 })
                }
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

/// 月列表 (F10)：按月倒序，每月一张卡片展示汇总。
private struct MonthListView: View {
    let months: [HistoryMonthSummary]
    let open: (YearMonth) -> Void

    /// 列表超过这个高度时滚动。
    private static let maxHeight: CGFloat = 520

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(months) { summary in
                    Button { open(summary.month) } label: { card(summary) }
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: Self.maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ summary: HistoryMonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.title).font(.headline)
                if let badge = summary.badge {
                    Text(badge)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            HistoryStatsGrid(stats: summary.stats)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

/// 汇总项网格，每行 3 项。
struct HistoryStatsGrid: View {
    let stats: [StatItem]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 8) {
            ForEach(stats, id: \.title) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.caption).foregroundStyle(.secondary)
                    Text(item.value).font(.callout.weight(.medium)).monospacedDigit()
                }
            }
        }
    }
}
