import SwiftUI
import WageCore

/// 历史 (PRD F10、F11)：月列表 → 月日历 → 单日详情，三级页面 (设计稿「历史-月列表」「历史-月日历」「历史-单日详情」大胆版)。
/// 三页都是墨色「账本」头图 (`HeroTheme.ledger`)，头图标题栏的返回胶囊逐级退回，月列表的返回关窗。
/// 日历里可改该月月薪，单日详情里可编辑那一天。所有文字取自快照，这里只管排版、导航与发命令。
struct HistoryView: View {
    let content: HistoryContent
    /// 单日编辑、改月薪发命令的口子 (#15)。
    let actions: PanelActions
    /// 月列表的返回：关掉历史窗口。
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
            MonthListView(months: snapshot.historyMonths(), open: { content.selectedMonth = $0 }, close: close)
        }
    }
}

/// 月列表 (F10，设计稿「历史-月列表」)：墨色头图写入职以来一共挣了多少 (各月合计) 与月数、扣款合计，小牛端着咖啡；
/// 下面按月倒序，每月一行，行间一条分隔线。往下滑头图收成窄栏。
private struct MonthListView: View {
    let months: [HistoryMonthSummary]
    let open: (YearMonth) -> Void
    let close: () -> Void

    var body: some View {
        let overview = HistoryOverview(months: months)
        HeroScroll { collapse in
            BoldHero(
                theme: .ledger,
                back: HeroBack(label: "返回", action: close),
                kicker: "入职以来一共挣了",
                caption: overview.caption,
                captionIcon: .list,
                cow: .pose(.working),
                bubble: HeroBubbleContent(value: "都记着呢", numeric: false),
                collapse: collapse,
                compactValue: heroCompactMoney(overview.total)
            ) {
                HeroAmount(text: overview.total, theme: .ledger, size: 76, maxWidth: 230)
            }
        } content: {
            VStack(spacing: 0) {
                ForEach(Array(months.enumerated()), id: \.element.id) { index, summary in
                    if index > 0 {
                        Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, Spacing.screen)
                    }
                    Button { open(summary.month) } label: { MonthRow(summary: summary) }
                        .buttonStyle(.highlight(radius: 0))
                }
            }
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s12)
        }
    }
}

/// 月列表里的一个月：月份大字 (Archivo Black) 与标签，右边结算总额 (本月橙色) 与箭头；
/// 下面一条细横条是这个月挣到满额工资的多少 (本月橙、其余墨色)，再下面一行小字 (应出勤、扣款、请假、白干)。
private struct MonthRow: View {
    let summary: HistoryMonthSummary

    private var tone: Color { summary.isCurrentMonth ? Palette.accent : Palette.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack(alignment: .center, spacing: Spacing.s10) {
                Text(summary.shortTitle).font(AppFont.heavy(21)).foregroundStyle(Palette.ink).lineLimit(1)
                if let badge = summary.badge {
                    MonthBadge(text: badge, isCurrent: summary.isCurrentMonth)
                }
                Spacer(minLength: Spacing.s8)
                Text(BoldNumber.grouped(summary.total)).font(AppFont.heavy(17)).foregroundStyle(tone).lineLimit(1).fixedSize()
                PhosphorIcon(.caretRight, size: 13).foregroundStyle(Palette.muted)
            }
            ProgressLine(progress: summary.progress, color: tone)
            Text(summary.figuresLine)
                .font(AppFont.num(11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s16)
        .contentShape(Rectangle())
    }
}

/// 月份旁的标签 (10/700)：本月高亮黄底墨字，安装当月 surface 底 muted 字。
private struct MonthBadge: View {
    let text: String
    let isCurrent: Bool

    var body: some View {
        Text(text)
            .font(AppFont.ui(10, .bold))
            .foregroundStyle(isCurrent ? Palette.ink : Palette.muted)
            .padding(.horizontal, Spacing.s6 + 1)
            .padding(.vertical, Spacing.s2)
            .background(isCurrent ? Palette.highlight : Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r6))
    }
}

/// 细横条：surface 底，前面 `progress` 那一截上色，圆头。
private struct ProgressLine: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.surface)
                Capsule().fill(color).frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}
