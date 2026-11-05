import SwiftUI
import WageCore

/// 月日历与单日详情 (PRD F11)，本票只读。颜色类型、详情文字都取自快照的 `HistoryMonth`。
struct MonthCalendarView: View {
    let month: HistoryMonth
    let back: () -> Void

    /// 点开的那一天；nil 时提示点某天。
    @State private var selectedDay: LocalDate?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HistoryStatsGrid(stats: month.summary.stats)
            calendarGrid
            legend
            Divider()
            if let day = month.days.first(where: { $0.date == selectedDay }) {
                DayDetailView(day: day)
            } else {
                Text("点某天看详情").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: back) { Label("月列表", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(month.summary.title).font(.headline)
            Spacer()
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 6) {
            ForEach(HistoryMonth.weekdayHeaders, id: \.self) { header in
                Text(header).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 34)
            }
            ForEach(month.days) { day in
                Button { selectedDay = day.date } label: { cell(day) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func cell(_ day: HistoryDay) -> some View {
        Text(day.dayText)
            .font(.callout.weight(day.isToday ? .bold : .regular))
            .monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(day.kind.color, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                // 今天描边，不遮住当天的颜色类型；选中的那天描得更粗。
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        day.isToday ? Color.accentColor : Color.primary.opacity(0.5),
                        lineWidth: day.date == selectedDay ? 2.5 : (day.isToday ? 1.5 : 0)
                    )
            }
            .contentShape(Rectangle())
    }

    /// 图例：各颜色类型与「今天」(PRD 4.6.1)。
    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(CalendarDayKind.legend, id: \.self) { kind in
                legendItem(kind.label) {
                    RoundedRectangle(cornerRadius: 3).fill(kind.color)
                }
            }
            legendItem(CalendarDayKind.todayLabel) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
    }

    private func legendItem(_ label: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: 4) {
            swatch().frame(width: 12, height: 12)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 单日详情：判定来源、结算、扣款明细、请假、白干段 (PRD 4.6.1)。
private struct DayDetailView: View {
    let day: HistoryDay

    var body: some View {
        let detail = day.detail
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(detail.title).font(.headline)
                Text(day.kind.label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(day.kind.color, in: Capsule())
                Spacer()
                Text("\(detail.sourceItem.title) \(detail.sourceItem.value)").font(.callout).foregroundStyle(.secondary)
            }
            if !detail.stats.isEmpty {
                HistoryStatsGrid(stats: detail.stats)
            }
            ForEach(detail.deductions) { item in
                line(title: item.title, detail: item.detail, value: item.amount)
            }
            if let leave = detail.leave {
                line(leave)
            }
            ForEach(Array(detail.unpaidWork.enumerated()), id: \.offset) { _, segment in
                line(segment)
            }
            if let summary = detail.unpaidWorkSummary {
                Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func line(_ line: HistoryLine) -> some View {
        self.line(title: line.title, detail: line.detail, value: line.value)
    }

    private func line(title: String, detail: String?, value: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).monospacedDigit()
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

extension CalendarDayKind {
    /// 日历格子的底色。
    var color: Color {
        switch self {
        case .fullAttendance: .green.opacity(0.3)
        case .deducted: .red.opacity(0.3)
        case .leave: .blue.opacity(0.3)
        case .rest: .gray.opacity(0.15)
        case .override: .purple.opacity(0.3)
        case .upcoming: .gray.opacity(0.05)
        }
    }
}
