import SwiftUI
import WageCore

/// 已到手：已完成的目标按达成年份分组，从目标页「已完成」标题行右侧的「已到手」进入，页头返回回到目标页。
/// 样式同目标页 (设计稿 P3 目标管理 · 760)：页头右侧是总结 (如「共 ¥4298 · 搬砖 4.3 天」)，
/// 每年一个小标题 (右边小计，如「2 件 · ¥4298」)，下面每个目标一行：对勾、名称、「10月30日 到手」，右边金额与「≈ 搬砖 1.9 天」。
/// 已完成冻结只能删 (AC-GOAL-10)，删除在悬停时出现的按钮或右键菜单里。
/// 文字原样取自快照 (`GoalList.completedYears`、`completedSummary`)。
struct GoalEarnedView: View {
    let list: GoalList
    let back: () -> Void
    let delete: (CompletedGoalRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("已到手", back: back) {
                if let summary = list.completedSummary {
                    Text(summary).font(AppFont.caption).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            if list.completed.isEmpty {
                Text("还没有到手的，先攒一个吧")
                    .font(AppFont.body)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollBody {
                    VStack(alignment: .leading, spacing: Spacing.s24) {
                        ForEach(list.completedYears) { year in
                            yearGroup(year)
                        }
                    }
                    .padding(Spacing.screen)
                }
            }
        }
    }

    /// 一年：小标题是年份，右边这一年的小计，下面这一年到手的目标。
    private func yearGroup(_ year: CompletedGoalYear) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack {
                GroupLabel(title: String(year.year))
                Spacer(minLength: Spacing.s8)
                Text(year.summary).font(AppFont.small).foregroundStyle(Palette.muted)
            }
            VStack(spacing: Spacing.s8) {
                ForEach(year.rows) { row in
                    EarnedGoalRowView(row: row, delete: { delete(row) })
                }
            }
        }
    }
}

/// 已到手的一行 (surface 底，整行 muted，同目标页的已完成行)：对勾、名称、到手日期，右边金额，金额下面折合搬砖天数 (日薪为 0 时没有)。
private struct EarnedGoalRowView: View {
    let row: CompletedGoalRow
    let delete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s10) {
            PhosphorIcon(.checkCircle, size: 16)
                .foregroundStyle(Palette.money)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(row.name).font(AppFont.bodySemibold).lineLimit(1)
                Text(row.receivedText).font(AppFont.small)
            }
            Spacer(minLength: Spacing.s8)
            if hovering {
                IconButton(systemName: "trash", help: "删除", action: delete)
            }
            VStack(alignment: .trailing, spacing: Spacing.s2) {
                Text(row.amountText).font(AppFont.num(13))
                if let workDays = row.workDaysText {
                    Text(workDays).font(AppFont.small)
                }
            }
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, Spacing.s14)
        .padding(.vertical, Spacing.s10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r10))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("删除", role: .destructive, action: delete)
        }
    }
}
