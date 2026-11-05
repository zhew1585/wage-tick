import SwiftUI
import WageCore

/// 月日历与单日详情 (PRD F11)。颜色类型、详情文字都取自快照的 `HistoryMonth`；
/// 单日详情里可编辑那一天 (#15)，月薪行可改该月月薪。
struct MonthCalendarView: View {
    let month: HistoryMonth
    let actions: PanelActions
    let back: () -> Void

    /// 点开的那一天；nil 时提示点某天。
    @State private var selectedDay: LocalDate?
    @State private var editingSalary = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HistoryStatsGrid(stats: month.summary.stats)
            salaryRow
            calendarGrid
            legend
            Divider()
            if let day = month.days.first(where: { $0.date == selectedDay }) {
                DayDetailView(day: day, actions: actions)
                    // 换一天时丢掉上一天的表单与提示。
                    .id(day.date)
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

    /// 该月月薪与「改月薪」入口 (PRD 4.2.1 #2)。
    private var salaryRow: some View {
        HStack {
            Text(month.salaryItem.title).font(.callout).foregroundStyle(.secondary)
            Text(month.salaryItem.value).font(.callout.weight(.medium)).monospacedDigit()
            Spacer()
            Button("改月薪") { editingSalary = true }
        }
        .sheet(isPresented: $editingSalary) {
            SalaryFormView(
                month: month.summary.month, title: month.summary.title, isCurrentMonth: month.summary.isCurrentMonth,
                current: month.monthlySalary, actions: actions,
                dismiss: { editingSalary = false }
            )
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
