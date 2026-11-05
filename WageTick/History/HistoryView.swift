import SwiftUI
import WageCore

/// 历史 (PRD F10、F11)：月列表 (设计稿 P4) → 月日历 (P5) → 单日详情 (P5 单日详情)，三级页面，页头返回逐级退回，月列表的返回关窗。
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

/// 月列表 (F10，设计稿 P4)：按月倒序，每月一行：月份与标签、结算总额，下面一排汇总项。
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
                    ForEach(months) { summary in
                        Button { open(summary.month) } label: { MonthRow(summary: summary) }
                            .buttonStyle(.highlight(radius: 0))
                        CardDivider()
                    }
                }
                .padding(.vertical, Spacing.s6)
            }
        }
    }
}

/// 月列表里的一个月。
private struct MonthRow: View {
    let summary: HistoryMonthSummary

    var body: some View {
        let stats = MonthStats(summary.stats)
        VStack(alignment: .leading, spacing: Spacing.s10) {
            HStack(spacing: Spacing.s8) {
                Text(summary.title).font(AppFont.sheetTitle).foregroundStyle(Palette.ink)
                if let badge = summary.badge {
                    Tag(badge, tone: summary.isCurrentMonth ? .money : .muted)
                }
                Spacer(minLength: Spacing.s8)
                if let total = stats.total {
                    Text(total.value).font(AppFont.num(15, .bold)).foregroundStyle(Palette.ink)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 13, height: 13)
            }
            HistoryStatsRow(stats: stats.rest)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s14)
        .contentShape(Rectangle())
    }
}

/// 月汇总拆成结算总额 (第一项，放标题右边) 与其余几项 (放下面一排)。顺序见 `HistoryMonthSummary.stats`。
struct MonthStats {
    let total: StatItem?
    let rest: [StatItem]

    init(_ stats: [StatItem]) {
        total = stats.first
        rest = Array(stats.dropFirst())
    }
}

/// 一排汇总项，等宽分栏：上面 10 号 muted 标题，下面 12/500 等宽数值；扣款类的数值不为零时用 loss 色。
struct HistoryStatsRow: View {
    let stats: [StatItem]

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s6) {
            ForEach(stats, id: \.title) { item in
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(item.title).font(AppFont.tiny).foregroundStyle(Palette.muted)
                    Text(item.value)
                        .font(AppFont.num(12, .medium))
                        .foregroundStyle(item.isLoss ? Palette.loss : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension StatItem {
    /// 数值是扣掉的钱 (核心写成「−¥100」)：标 loss 色。
    var isLoss: Bool { value.hasPrefix("−") }
}

/// 设计稿月列表的小标签 (10/600，圆角 10，左右 7 上下 2)：本月 money 色，其余 muted。
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
