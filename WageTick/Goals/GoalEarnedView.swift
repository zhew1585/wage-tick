import SwiftUI
import WageCore

/// 已到手 (大胆版设计稿「目标-已到手」)：从目标页底部「已到手 N」进入，返回胶囊回到目标页。
/// 绿色头图：「这些都是自己挣的」、已完成个数、总额与折合搬砖天数，撒钱小牛。
/// 下面按达成年份分组 (年份大字 + 小计)，左边一条时间线 (最近一件实心绿点，其余空心)；
/// 每行名称、「10月28日 到手」，右边金额与「≈ 搬砖 1.9 天」。已完成冻结只能删 (AC-GOAL-10)，删除在悬停按钮或右键菜单里。
/// 文字原样取自快照 (`GoalList.completedYears`、`completedSummary`)。
struct GoalEarnedView: View {
    let list: GoalList
    let back: () -> Void
    let delete: (CompletedGoalRow) -> Void

    var body: some View {
        CollapsingHeroScroll { collapse in
            hero(collapse: collapse)
        } content: {
            if list.completed.isEmpty {
                Text("还没有到手的，先攒一个吧")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
            } else {
                years
            }
        }
    }

    private func hero(collapse: CGFloat) -> some View {
        let count = "\(list.completed.count)"
        let unit = "件到手"
        return BoldHero(
            theme: .mint,
            back: HeroBack(label: "目标", action: back),
            kicker: heroKicker("这些都是自己挣的", collapsed: unit, collapse: collapse),
            caption: nil,
            cow: .pose(.paid),
            bubble: HeroBubbleContent(value: "都是血汗钱", numeric: false),
            collapse: collapse,
            compactValue: count
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HeroCount(value: count, unit: unit, theme: .mint)
                if let summary = list.completedSummary {
                    HeroInkCaption(icon: .GoalIcon.hammer, text: summary)
                }
            }
        }
    }

    private var years: some View {
        let newest = list.completed.first?.id
        return VStack(alignment: .leading, spacing: Spacing.s18) {
            ForEach(list.completedYears) { year in
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(year.year)).font(AppFont.heavy(20)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text(year.summary).font(AppFont.num(11)).foregroundStyle(Palette.muted)
                    }
                    .padding(.bottom, Spacing.s4)
                    ForEach(Array(year.rows.enumerated()), id: \.element.id) { index, row in
                        EarnedGoalRow(
                            row: row,
                            isNewest: row.id == newest,
                            isFirst: index == 0,
                            isLast: index == year.rows.count - 1,
                            delete: { delete(row) }
                        )
                    }
                }
            }
        }
        .padding(EdgeInsets(top: Spacing.s20, leading: Spacing.screen, bottom: Spacing.s20, trailing: Spacing.screen))
    }
}

/// 已到手的一行：左边时间线圆点 (最近一件实心绿、其余空心) 与竖线，名称与到手日期，右边金额与折合搬砖天数，下沿一条分隔线。
/// 悬停时金额前出现删除按钮。
private struct EarnedGoalRow: View {
    let row: CompletedGoalRow
    let isNewest: Bool
    /// 这一年的第一行、最后一行：时间线竖线不再往上、往下延。
    let isFirst: Bool
    let isLast: Bool
    let delete: () -> Void

    @State private var hovering = false

    private static let rail: CGFloat = 26

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            timeline.frame(width: Self.rail)
            HStack(alignment: .top, spacing: Spacing.s8) {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    Text(row.name).font(AppFont.ui(14, .bold)).foregroundStyle(Palette.ink)
                    Text(row.receivedText).font(AppFont.small).foregroundStyle(Palette.muted)
                }
                .lineLimit(1)
                Spacer(minLength: Spacing.s4)
                if hovering {
                    IconButton(systemName: "trash", help: "删除", action: delete).padding(.top, Spacing.s2)
                }
                VStack(alignment: .trailing, spacing: Spacing.s4) {
                    Text(row.amountText).font(AppFont.heavy(15)).foregroundStyle(Palette.ink)
                    if let workDays = row.workDaysText {
                        Text(workDays).font(AppFont.num(10)).foregroundStyle(Palette.muted)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
            .padding(.vertical, Spacing.s12)
            .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("删除", role: .destructive, action: delete)
        }
    }

    /// 圆点对齐名称那一行；竖线穿过整行把上下圆点连起来，一年的第一行从圆点起、最后一行到圆点止。
    private var timeline: some View {
        VStack(spacing: 0) {
            (isFirst ? Color.clear : Palette.line).frame(width: 2, height: Self.dotTop)
            Circle()
                .fill(isNewest ? Palette.money : Palette.bg)
                .overlay(Circle().strokeBorder(Palette.ink, lineWidth: 2))
                .frame(width: Self.dot, height: Self.dot)
            (isLast ? Color.clear : Palette.line).frame(width: 2).frame(maxHeight: .infinity)
        }
        .padding(.leading, -Spacing.s4)
    }

    private static let dot: CGFloat = 12
    /// 圆点上沿离行顶的距离，让圆点和名称那一行居中对齐。
    private static let dotTop: CGFloat = 16
}
