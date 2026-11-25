import SwiftUI
import WageCore

/// 月日历 (PRD F11，设计稿 P5 月日历 · 760)：页头月份与上下月切换，月薪条 (可改该月月薪)，日历格子与图例，底部月小结。
/// 颜色类型、格子金额与小字、月薪条、月小结的文字都取自快照的 `HistoryMonth`；点某天进单日详情。
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

    private static let columnSpacing: CGFloat = Spacing.s4
    private static let rowSpacing = Spacing.s5
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(month.summary.title, back: back) { monthSwitcher }
            ScrollBody {
                VStack(spacing: 0) {
                    salaryRow
                    calendarGrid
                        .padding(.horizontal, Spacing.s14)
                        .padding(.top, Spacing.s16)
                        .padding(.bottom, Spacing.s10)
                    CalendarLegend()
                        .padding(.horizontal, Spacing.screen)
                        .padding(.top, Spacing.s8)
                        .padding(.bottom, Spacing.s18)
                }
            }
            HistoryFiguresRow(figures: month.footer, valueFont: AppFont.num(14, .semibold))
                .padding(.horizontal, Spacing.screen)
                .padding(.top, Spacing.s14)
                .padding(.bottom, Spacing.s16)
                .background(Palette.surface)
                .overlay(alignment: .top) { CardDivider() }
        }
    }

    /// 上一个月 (更早)、下一个月 (更晚)；到头了变淡、点不动。
    private var monthSwitcher: some View {
        let index = months.firstIndex(of: month.summary.month)
        let older = index.flatMap { months.indices.contains($0 + 1) ? months[$0 + 1] : nil }
        let newer = index.flatMap { $0 > 0 ? months[$0 - 1] : nil }
        return HStack(spacing: Spacing.s16) {
            switchButton(.caretLeft, help: "上个月", target: older)
            switchButton(.caretRight, help: "下个月", target: newer)
        }
    }

    private func switchButton(_ icon: Phosphor, help: String, target: YearMonth?) -> some View {
        Button {
            if let target { switchMonth(target) }
        } label: {
            PhosphorIcon(icon, size: 16).foregroundStyle(Palette.muted)
        }
        .buttonStyle(.highlight(radius: Radius.r4, outset: Spacing.s3))
        .help(help)
        .disabled(target == nil)
        .opacity(target == nil ? 0.35 : 1)
    }

    /// 该月工资：按月为「¥20000 → 日薪 ¥1000」，按天为「¥200 · 满勤 ¥4200」；点整条或铅笔改该月工资 (PRD 4.2.1 #2)，surface 底。
    private var salaryRow: some View {
        HStack(spacing: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(month.salaryCaption).font(AppFont.caption).foregroundStyle(Palette.muted)
                Text(month.salaryText).font(AppFont.num(15, .semibold)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: Spacing.s8)
            PhosphorIcon(.pencilSimple, size: 15).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s14)
        .background(Palette.surface)
        .contentShape(Rectangle())
        .onTapGesture { editingSalary = true }
        .hoverFeedback()
        .help("改这个月的工资")
        .sheet(isPresented: $editingSalary) {
            SalaryFormView(
                month: month.summary.month, title: month.summary.title, isCurrentMonth: month.summary.isCurrentMonth,
                current: month.salary, basis: month.payBasis, actions: actions,
                dismiss: { editingSalary = false }
            )
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: Self.rowSpacing) {
            ForEach(HistoryMonth.weekdayHeaders, id: \.self) { header in
                Text(header)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.muted)
                    .padding(.bottom, Spacing.s4)
            }
            ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: DayCell.height)
            }
            ForEach(month.days) { day in
                Button { open(day.date) } label: { DayCell(day: day) }
                    .buttonStyle(InteractiveButtonStyle { label, state in
                        label.environment(\.dayCellInteraction, state)
                    })
                    .help(day.detail.title)
            }
        }
    }
}

/// 日历里的一天 (44×70、圆角 9)：日号 14 号等宽；被扣钱下面一个小圆点，请假、单日覆盖下面一行小字 (`HistoryDay.tag`)，
/// 已过的应出勤日和今天最下面是当天金额 (`HistoryDay.amountText`)。
/// 今天整格 ink 底，盖过当天的颜色类型 (设计稿)；小圆点、小字与金额照常显示。
/// 悬停时描一圈 1.5 的边 (颜色见 `DayCellStyle.hoverStroke`)，按下再叠一层底；手型光标。
private struct DayCell: View {
    let day: HistoryDay
    @Environment(\.dayCellInteraction) private var interaction

    static let height: CGFloat = 70
    private static let dotSize: CGFloat = 5

    var body: some View {
        let style = DayCellStyle(kind: day.kind, isToday: day.isToday)
        let shape = RoundedRectangle(cornerRadius: Radius.r9)
        VStack(spacing: Spacing.s4) {
            Text(day.dayText)
                .font(AppFont.num(14, style.isEmphasized ? .semibold : .regular))
                .foregroundStyle(style.text)
            if day.kind == .deducted {
                Circle().fill(Palette.lossDot).frame(width: Self.dotSize, height: Self.dotSize)
            }
            if let tag = day.tag {
                Text(tag).font(AppFont.tiny).foregroundStyle(style.text).lineLimit(1)
            }
            if let amount = day.amountText {
                Text(amount)
                    .font(AppFont.num(10, .medium))
                    .foregroundStyle(style.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(style.fill, in: shape)
        .overlay {
            if interaction.isHovered || interaction.isPressed {
                shape.strokeBorder(style.hoverStroke, lineWidth: 1.5)
            } else if let stroke = style.stroke {
                shape.strokeBorder(stroke, lineWidth: 1)
            }
        }
        .overlay(interaction.isPressed ? shape.fill(Palette.pressedOverlay) : nil)
        .contentShape(shape)
    }
}

private extension EnvironmentValues {
    /// 日历格子按钮的交互状态，由格子按钮的样式传给 `DayCell`。
    @Entry var dayCellInteraction = InteractionState()
}

/// 日历格子按颜色类型的样子 (设计稿 P5 月日历 · 760)：
/// - 满勤 money-soft 底 money 字，被扣钱 loss-soft 底 loss 字，请假 accent-soft 底 accent 字
/// - 未到 (未来的应出勤日) 白底 line 描边 ink 字
/// - 休息日无底无框、muted 细字；改成不上班无底、muted 描边、muted 细字
/// - 今天 ink 底、bg 字
private struct DayCellStyle {
    let fill: Color
    let stroke: Color?
    let text: Color
    /// 日号用 600 字重；休息日、改成不上班用 400。
    let isEmphasized: Bool
    /// 悬停时的描边：与日号同色 (满勤 money、扣钱 loss……)；今天 (ink 底) 用 accent，改成不上班 (本来就是 muted 框) 用 ink。
    let hoverStroke: Color

    init(kind: CalendarDayKind, isToday: Bool) {
        hoverStroke = isToday ? Palette.accent : kind == .override ? Palette.ink : Self.textColor(kind)
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

    /// 非今天的日号颜色，与上面的表一致。
    private static func textColor(_ kind: CalendarDayKind) -> Color {
        switch kind {
        case .fullAttendance: Palette.money
        case .deducted: Palette.loss
        case .leave: Palette.accent
        case .upcoming: Palette.ink
        case .rest, .override: Palette.muted
        }
    }
}

/// 图例：核心 `CalendarDayKind.legend` 列出的类型 (顺序与文案取自核心) 与「今天」，一行两端对齐。
private struct CalendarLegend: View {
    private static let swatchSize: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarDayKind.legend, id: \.self) { kind in
                item(kind.label) { swatch(kind) }
                Spacer(minLength: Spacing.s8)
            }
            item(CalendarDayKind.todayLabel) {
                RoundedRectangle(cornerRadius: Radius.r2).fill(Palette.ink)
            }
        }
    }

    /// 色块与格子对应；被扣钱用小圆点的颜色 (设计稿)。
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
            Text(label).font(AppFont.small).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .fixedSize()
    }
}
