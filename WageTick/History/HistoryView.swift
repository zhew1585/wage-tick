import SwiftUI
import WageCore

/// 历史 (PRD F10、F11)：月列表 (设计稿 P4 · 760) → 月日历 (P5 · 760) → 单日详情 (P5 单日详情 · 760)，三级页面，页头返回逐级退回，月列表的返回关窗。
/// 日历里可改该月月薪，单日详情里可编辑那一天。所有文字取自快照，这里只管排版、导航与发命令。
struct HistoryView: View {
    let content: HistoryContent
    /// 单日编辑、改月薪发命令的口子 (#15)。
    let actions: PanelActions
    let close: () -> Void

    var body: some View {
        Group {
            if let snapshot = content.snapshot {
                page(snapshot)
            }
        }
        .frame(width: Spacing.pageWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func page(_ snapshot: Snapshot) -> some View {
        if let date = content.selectedDay, let day = snapshot.historyDay(date) {
            DayDetailView(day: day, actions: actions, back: { content.selectedDay = nil })
                // 换一天时丢掉上一天的表单与提示。
                .id(day.date)
        } else if let month = content.selectedMonth.flatMap(snapshot.historyMonth) {
            let months = snapshot.historyMonths().map(\.month)
            MonthCalendarView(
                month: month, months: months, actions: actions,
                open: { content.selectedDay = $0 },
                switchMonth: { content.selectedMonth = $0 },
                back: { content.selectedMonth = nil }
            )
            // 换月时丢掉上个月的表单。
            .id(month.summary.month)
        } else {
            MonthListView(months: snapshot.historyMonths(), open: { content.selectedMonth = $0 }, back: close)
        }
    }
}

/// 月列表 (F10，设计稿 P4 历史月列表 · 760)：按月倒序，每月一行：月份与标签、结算总额，下面一排四项汇总；行间一条分隔线。
private struct MonthListView: View {
    let months: [HistoryMonthSummary]
    let open: (YearMonth) -> Void
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("历史", back: back) {
                Text("按月倒序").font(AppFont.caption).foregroundStyle(Palette.muted)
            }
            ScrollBody {
                VStack(spacing: 0) {
                    ForEach(Array(months.enumerated()), id: \.element.id) { index, summary in
                        if index > 0 { CardDivider() }
                        Button { open(summary.month) } label: { MonthRow(summary: summary) }
                            .buttonStyle(.highlight(radius: 0))
                    }
                }
                .padding(.vertical, Spacing.s4)
            }
        }
    }
}

/// 月列表里的一个月：月份 15/700 与标签，右边结算总额 15/700 与箭头；下面应出勤、扣款、请假、白干四项。
private struct MonthRow: View {
    let summary: HistoryMonthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            HStack(spacing: Spacing.s8) {
                Text(summary.title).font(AppFont.ui(15, .bold)).foregroundStyle(Palette.ink)
                if let badge = summary.badge {
                    Tag(badge, tone: summary.isCurrentMonth ? .money : .muted)
                }
                Spacer(minLength: Spacing.s8)
                HStack(spacing: Spacing.s6) {
                    Text(summary.total).font(AppFont.num(15, .bold)).foregroundStyle(Palette.ink)
                    PhosphorIcon(.caretRight, size: 13).foregroundStyle(Palette.muted)
                }
            }
            HistoryFiguresRow(figures: summary.figures)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s14 + 1)
        .contentShape(Rectangle())
    }
}

/// 一排汇总项，等宽四栏：上面 11 号 muted 短标题，下面等宽数值 (月列表 13/500，月日历底部 14/600)；扣款不为零时用 loss 色。
struct HistoryFiguresRow: View {
    let figures: [HistoryFigure]
    var valueFont = AppFont.num(13, .medium)

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s6) {
            ForEach(figures, id: \.title) { figure in
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text(figure.title).font(AppFont.small).foregroundStyle(Palette.muted)
                    Text(figure.value)
                        .font(valueFont)
                        .foregroundStyle(figure.isLoss ? Palette.loss : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// 设计稿月列表的小标签 (10/600，圆角 10，左右 7 上下 2)：本月 money 色，安装当月 muted。
struct Tag: View {
    enum Tone {
        case money, muted
    }

    let text: String
    let tone: Tone

    init(_ text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(AppFont.ui(10, .semibold))
            .foregroundStyle(tone == .money ? Palette.money : Palette.muted)
            .padding(.horizontal, Spacing.s6 + 1)
            .padding(.vertical, Spacing.s2)
            .background(tone == .money ? Palette.moneySoft : Palette.surface, in: Capsule())
    }
}
