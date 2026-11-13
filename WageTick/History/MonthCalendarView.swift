import SwiftUI
import WageCore

/// 月日历 (PRD F11，设计稿「历史-月日历」)：墨色头图写「2026年11月 · 已结算」与已结算金额、应出勤与日薪，
/// 标题栏右侧是改工资与上下月切换；下面日历格子与图例，最底下固定一行本月扣款、请假、白干。
/// 颜色类型、格子金额与小字、各项文字都取自快照的 `HistoryMonth`；点某天进单日详情。
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

    private static let columnSpacing: CGFloat = 4.5
    private static let rowSpacing: CGFloat = 7
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: columnSpacing), count: 7)

    private var summary: HistoryMonthSummary { month.summary }

    var body: some View {
        VStack(spacing: 0) {
            HeroScroll { collapse in
                hero(collapse)
            } content: {
                VStack(spacing: 0) {
                    // 排满 6 行的月份 (如 2026 年 11 月) 也要一屏放下、不能空滑：上下留白收紧到 12 / 12 / 10。
                    calendarGrid
                        .padding(.horizontal, Spacing.s16)
                        .padding(.top, Spacing.s12)
                    CalendarLegend(showsOverride: month.days.contains { $0.kind == .override })
                        .padding(.horizontal, Spacing.s16)
                        .padding(.top, Spacing.s12)
                        .padding(.bottom, Spacing.s10)
                }
            }
            // 已结算在头图里，底部只放扣款、请假、白干。
            HistoryStatsBar(figures: [summary.deduction, summary.leave, summary.unpaidWork])
        }
        .sheet(isPresented: $editingSalary) {
            SalaryFormView(
                month: summary.month, title: summary.title, isCurrentMonth: summary.isCurrentMonth,
                current: month.salary, basis: month.payBasis, actions: actions,
                dismiss: { editingSalary = false }
            )
        }
    }

    /// 头图：标题「2026年11月 · 已结算」，大数字结算总额，说明「应出勤 20 天 · 日薪 ¥1000」；本月小牛说还早呢。
    private func hero(_ collapse: CGFloat) -> some View {
        let settledTitle = month.footer.first?.title ?? "已结算"
        return BoldHero(
            theme: .ledger,
            back: HeroBack(label: "历史", action: back),
            kicker: "\(summary.title) · \(settledTitle)",
            caption: month.heroCaption,
            captionIcon: .calendarBlank,
            cow: .pose(.working),
            bubble: HeroBubbleContent(value: summary.isCurrentMonth ? "还早呢" : "结清了", numeric: false),
            collapse: collapse,
            compactValue: heroCompactMoney(summary.total)
        ) {
            HeroAmount(text: summary.total, theme: .ledger, size: 76, maxWidth: 220)
        }
        .overlay(alignment: .topTrailing) { titlebarTools }
    }

    /// 标题栏右侧：改这个月的工资 (PRD 4.2.1 #2)，上一个月 (更早)、下一个月 (更晚)；到头了变淡、点不动。
    private var titlebarTools: some View {
        let index = months.firstIndex(of: summary.month)
        let older = index.flatMap { months.indices.contains($0 + 1) ? months[$0 + 1] : nil }
        let newer = index.flatMap { $0 > 0 ? months[$0 - 1] : nil }
        return HeroTitlebarTrailing {
            HeroChipButton(icon: .pencilSimple, title: "工资", help: "改这个月的工资", theme: .ledger) { editingSalary = true }
            HeroChipButton(icon: .caretLeft, help: "上个月", isEnabled: older != nil, theme: .ledger) {
                if let older { switchMonth(older) }
            }
            HeroChipButton(icon: .caretRight, help: "下个月", isEnabled: newer != nil, theme: .ledger) {
                if let newer { switchMonth(newer) }
            }
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

/// 日历里的一天 (43 高、圆角 10)：日号 Archivo Black 14，下面一行小字：请假、单日覆盖写 `HistoryDay.tag`，
/// 否则已过的应出勤日和今天写当天金额 (`HistoryDay.amountText`)。
/// 悬停时描一圈 1.5 的边，按下再叠一层底；手型光标。
private struct DayCell: View {
    let day: HistoryDay
    @Environment(\.dayCellInteraction) private var interaction

    static let height: CGFloat = 43

    var body: some View {
        let style = DayCellStyle(kind: day.kind, isToday: day.isToday)
        let shape = RoundedRectangle(cornerRadius: Radius.r10)
        VStack(spacing: 0) {
            Text(day.dayText)
                .font(AppFont.heavy(14))
                .foregroundStyle(style.text)
            if let note = day.tag ?? day.amountText {
                Text(note)
                    .font(day.tag == nil ? AppFont.num(9) : AppFont.ui(9, .medium))
                    .foregroundStyle(style.note)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, Spacing.s2)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(style.fill, in: shape)
        .overlay {
            if interaction.isHovered || interaction.isPressed {
                shape.strokeBorder(style.hoverStroke, lineWidth: 1.5)
            } else if let stroke = style.stroke {
                shape.strokeBorder(stroke.color, style: stroke.style)
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

/// 日历格子按颜色类型的样子 (设计稿「历史-月日历」)，颜色只用墨色、高亮黄与头图橙：
/// - 满勤墨色底白字白金额，被扣钱墨色底白字、金额用扣钱的红；请假高亮黄底墨字
/// - 未到 (未来的应出勤日) surface 浅底墨字；休息日无底 muted 字；改成不上班无底 muted 字、muted 虚线框
/// - 今天 bg 底、橙色 2pt 描边、金额橙色，盖过当天的颜色类型
private struct DayCellStyle {
    let fill: Color
    let stroke: (color: Color, style: StrokeStyle)?
    let text: Color
    /// 日号下面那行小字 (金额或标签) 的颜色。
    let note: Color
    /// 悬停时的描边：墨色底的格子用橙色，其余用墨色。
    let hoverStroke: Color

    init(kind: CalendarDayKind, isToday: Bool) {
        if isToday {
            (fill, stroke, text, note, hoverStroke) = (Palette.bg, (Palette.accent, StrokeStyle(lineWidth: 2)), Palette.ink, Palette.accent, Palette.ink)
            return
        }
        (fill, stroke, text, note, hoverStroke) = switch kind {
        case .fullAttendance: (Palette.ink, nil, .white, .white.opacity(0.85), Palette.accent)
        case .deducted: (Palette.ink, nil, .white, Palette.lossDot, Palette.accent)
        case .leave: (Palette.highlight, nil, Palette.ink, Palette.ink, Palette.ink)
        case .upcoming: (Palette.surface, nil, Palette.ink, Palette.muted, Palette.ink)
        case .rest: (.clear, nil, Palette.muted.opacity(0.75), Palette.muted, Palette.ink)
        case .override: (.clear, (Palette.muted, StrokeStyle(lineWidth: 1, dash: [3, 2])), Palette.muted.opacity(0.75), Palette.muted, Palette.ink)
        }
    }
}

/// 图例：满勤、被扣钱、请假 (文案取自核心 `CalendarDayKind`)、今天、休息日；这个月有改成不上班的日子时再加一项。
private struct CalendarLegend: View {
    let showsOverride: Bool

    private static let swatchSize: CGFloat = 11

    var body: some View {
        // 6 项时一行刚好放得下 (宽 328)，间距别再加大，否则撑宽整页。
        HStack(spacing: Spacing.s8) {
            item(CalendarDayKind.fullAttendance.label) { shape.fill(Palette.ink) }
            item(CalendarDayKind.deducted.label) {
                shape.fill(Palette.ink).overlay(shape.strokeBorder(Palette.lossDot, lineWidth: 1.5))
            }
            item(CalendarDayKind.leave.label) { shape.fill(Palette.highlight) }
            item(CalendarDayKind.todayLabel) { shape.strokeBorder(Palette.accent, lineWidth: 1.5) }
            item(CalendarDayKind.rest.label) { shape.strokeBorder(Palette.line, lineWidth: 1.5) }
            if showsOverride {
                item(CalendarDayKind.override.label) {
                    shape.strokeBorder(Palette.muted, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.r2) }

    private func item(_ label: String, @ViewBuilder swatch: () -> some View) -> some View {
        HStack(spacing: Spacing.s4) {
            swatch().frame(width: Self.swatchSize, height: Self.swatchSize)
            Text(label).font(AppFont.small).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .fixedSize()
    }
}
