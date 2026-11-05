import SwiftUI
import WageCore

/// 月日历 (PRD F11，设计稿 P5 月日历)：页头月份与上下月切换，月薪条 (可改该月月薪)，日历格子与图例。
/// 颜色类型、文字都取自快照的 `HistoryMonth`；点某天进单日详情。
struct MonthCalendarView: View {
    let month: HistoryMonth
    /// 能看的月份 (安装当月至本月，倒序)，上下月切换按它判断有没有上一个、下一个月。
    let months: [YearMonth]
    let actions: PanelActions
    /// 点开某一天。
    let open: (LocalDate) -> Void
    let switchMonth: (YearMonth) -> Void
    let back: () -> Void

    @State private var editingSalary = false

    private static let cellSpacing: CGFloat = Spacing.s4
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(month.summary.title, back: back) { monthSwitcher }
            salaryRow
            calendarGrid
                .padding(.horizontal, Spacing.s14)
                .padding(.top, Spacing.s14)
                .padding(.bottom, Spacing.s8)
            CalendarLegend()
                .padding(.horizontal, Spacing.screen)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s16)
        }
    }

    /// 上一个月 (更早)、下一个月 (更晚)；到头了变淡、点不动。
    private var monthSwitcher: some View {
        let index = months.firstIndex(of: month.summary.month)
        let older = index.flatMap { months.indices.contains($0 + 1) ? months[$0 + 1] : nil }
        let newer = index.flatMap { $0 > 0 ? months[$0 - 1] : nil }
        return HStack(spacing: Spacing.s14) {
            switchButton("chevron.left", help: "上个月", target: older)
            switchButton("chevron.right", help: "下个月", target: newer)
        }
    }

    private func switchButton(_ systemName: String, help: String, target: YearMonth?) -> some View {
        IconButton(systemName: systemName, help: help) {
            if let target { switchMonth(target) }
        }
        .disabled(target == nil)
        .opacity(target == nil ? 0.35 : 1)
    }

    /// 该月月薪与「改月薪」入口 (PRD 4.2.1 #2)，surface 底。标题后跟该月应出勤日数。
    private var salaryRow: some View {
        let attendance = month.summary.stats.dropFirst().first
        let caption = [month.salaryItem.title, attendance.map { "\($0.title) \($0.value)" }].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(caption).font(AppFont.small).foregroundStyle(Palette.muted)
                Text(month.salaryItem.value).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: Spacing.s8)
            IconButton(systemName: "pencil", help: "改这个月的月薪") { editingSalary = true }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s12)
        .background(Palette.surface)
        .contentShape(Rectangle())
        .onTapGesture { editingSalary = true }
        .sheet(isPresented: $editingSalary) {
            SalaryFormView(
                month: month.summary.month, title: month.summary.title, isCurrentMonth: month.summary.isCurrentMonth,
                current: month.monthlySalary, actions: actions,
                dismiss: { editingSalary = false }
            )
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: Self.cellSpacing) {
            ForEach(HistoryMonth.weekdayHeaders, id: \.self) { header in
                Text(header)
                    .font(AppFont.small)
                    .foregroundStyle(Palette.muted)
                    .frame(height: 16)
                    .padding(.bottom, Spacing.s4)
            }
            ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: DayCell.height)
            }
            ForEach(month.days) { day in
                Button { open(day.date) } label: { DayCell(day: day) }
                    .buttonStyle(.plain)
                    .help(day.detail.title)
            }
        }
    }
}

/// 日历里的一天 (高 42、圆角 8)：日号 12 号等宽，被扣钱下面一个小圆点，请假下面一行请假类型小字。
/// 今天整格 ink 底，盖过当天的颜色类型 (设计稿)；小圆点与小字照常显示。
private struct DayCell: View {
    let day: HistoryDay

    static let height: CGFloat = 42
    private static let dotSize: CGFloat = 5

    var body: some View {
        let style = DayCellStyle(kind: day.kind, isToday: day.isToday)
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        VStack(spacing: Spacing.s3) {
            Text(day.dayText)
                .font(AppFont.num(12, style.isEmphasized ? .semibold : .regular))
                .foregroundStyle(style.text)
            if day.kind == .deducted {
                Circle().fill(Palette.lossDot).frame(width: Self.dotSize, height: Self.dotSize)
            } else if day.kind == .leave, let leave = day.detail.leave {
                Text(leave.title).font(AppFont.ui(8)).foregroundStyle(style.text).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(style.fill, in: shape)
        .overlay {
            if let stroke = style.stroke {
                shape.strokeBorder(stroke, lineWidth: 1)
            }
        }
        .contentShape(shape)
    }
}

/// 日历格子按颜色类型的样子 (设计稿 P5 月日历)：
/// - 满勤 money-soft 底 money 字，被扣钱 loss-soft 底 loss 字，请假 accent-soft 底 accent 字
/// - 未到 (未来的应出勤日) 白底 line 描边 ink 字
/// - 休息日无底无框、muted 细字；单日覆盖无底、muted 描边、muted 细字
/// - 今天 ink 底、bg 字
private struct DayCellStyle {
    let fill: Color
    let stroke: Color?
    let text: Color
    /// 日号用 600 字重；休息日、单日覆盖用 400。
    let isEmphasized: Bool

    init(kind: CalendarDayKind, isToday: Bool) {
        if isToday {
            (fill, stroke, text, isEmphasized) = (Palette.ink, nil, Palette.bg, true)
            return
        }
        (fill, stroke, text, isEmphasized) = switch kind {
        case .fullAttendance: (Palette.moneySoft, nil, Palette.money, true)
        case .deducted: (Palette.lossSoft, nil, Palette.loss, true)
        case .leave: (Palette.accentSoft, nil, Palette.accent, true)
        case .upcoming: (Palette.card, Palette.line, Palette.ink, true)
        case .rest: (.clear, nil, Palette.muted, false)
        case .override: (.clear, Palette.muted, Palette.muted, false)
        }
    }
}

/// 图例：各颜色类型 (顺序与文案取自核心 `CalendarDayKind.legend`) 与「今天」(PRD 4.6.1)，放不下时换行。
private struct CalendarLegend: View {
    private static let swatchSize: CGFloat = 9

    var body: some View {
        FlowLayout(spacing: Spacing.s12, lineSpacing: Spacing.s6) {
            ForEach(CalendarDayKind.legend, id: \.self) { kind in
                item(kind.label) { swatch(kind) }
            }
            item(CalendarDayKind.todayLabel) {
                RoundedRectangle(cornerRadius: Radius.r2).fill(Palette.ink)
            }
        }
    }

    /// 色块与格子对应；被扣钱用小圆点的颜色 (设计稿)，休息日格子无底无框，色块用虚线框示意。
    @ViewBuilder
    private func swatch(_ kind: CalendarDayKind) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r2)
        switch kind {
        case .fullAttendance: shape.fill(Palette.moneySoft)
        case .deducted: shape.fill(Palette.lossDot)
        case .leave: shape.fill(Palette.accentSoft)
        case .upcoming: shape.fill(Palette.card).overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
        case .rest: shape.strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
        case .override: shape.strokeBorder(Palette.muted, lineWidth: 1)
        }
    }

    private func item(_ label: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: Spacing.s4) {
            swatch().frame(width: Self.swatchSize, height: Self.swatchSize)
            Text(label).font(AppFont.tiny).foregroundStyle(Palette.muted)
        }
    }
}

/// 从左到右排、放不下就换行的布局 (图例用)。
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
