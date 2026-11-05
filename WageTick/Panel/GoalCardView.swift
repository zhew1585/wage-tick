import SwiftUI
import WageCore

/// 面板目标区 (PRD F9，设计稿 P2 Goals)：文字和进度原样取自快照的 `GoalCard` 与 `GoalQueueSection`。
/// 累计中目标一行：旗子图标、名称、预计完成，下方 4pt 进度条；排队中目标图标换成沙漏、整行 muted、进度条为空。
/// 队列为空时整行可点，进入目标管理；有排队中目标时下方是「显示更多 (N)」或展开后的排队目标与「收起」。
struct GoalCardView: View {
    let card: GoalCard
    /// 排队部分；没有排队中目标时为 nil，不显示「显示更多」(AC-GPRG-08)。
    let queue: GoalQueueSection?
    let openGoals: () -> Void
    /// 点「显示更多」或「收起」：发 `.toggleGoalQueueExpanded`，展开状态由核心记住【O3】。
    let toggleQueue: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s12) {
            mainRow
            if let queue {
                ForEach(queue.queued) { goal in
                    GoalRowView(icon: .hourglassSimple, name: goal.name, estimate: goal.estimate, progress: 0, muted: true)
                        .help(goal.amountText)
                }
                toggleButton(queue)
            }
        }
        .padding(EdgeInsets(top: Spacing.s14, leading: Spacing.screen, bottom: queue == nil ? Spacing.s14 : Spacing.s10, trailing: Spacing.screen))
    }

    @ViewBuilder
    private var mainRow: some View {
        switch card {
        case .empty(let prompt):
            Button(action: openGoals) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                    PhosphorIcon(.flagBanner, size: 13).iconOnTextBaseline()
                    Text(prompt).font(AppFont.captionSemibold)
                    Spacer()
                    PhosphorIcon(.caretRight, size: 11)
                }
                .foregroundStyle(Palette.muted)
                .padding(.vertical, Spacing.s2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.highlight(radius: Radius.r6, outset: Spacing.s6))
        case .active(let goal):
            // 设计稿不展示金额，悬停时显示「¥3000 / ¥10000」。
            GoalRowView(icon: .flagBanner, name: goal.name, estimate: goal.estimate, progress: goal.progress, muted: false)
                .help(goal.amountText)
        }
    }

    /// 「显示更多 (2)」+ 向下箭头，展开后「收起」+ 向上箭头，居中。
    private func toggleButton(_ queue: GoalQueueSection) -> some View {
        Button(action: toggleQueue) {
            HStack(spacing: Spacing.s4) {
                Text(queue.toggleTitle).font(AppFont.ui(11, .medium))
                PhosphorIcon(queue.queued.isEmpty ? .caretDown : .caretUp, size: 11)
            }
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: Radius.r6))
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.s2)
    }
}

/// 目标区的一行：图标 13、名称 12/600、右侧预计 11，下方 4pt 进度条。
private struct GoalRowView: View {
    let icon: Phosphor
    let name: String
    let estimate: String
    /// 进度条比例，0 至 1。
    let progress: Double
    /// 排队中：图标与名称都用 muted。
    let muted: Bool

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                PhosphorIcon(icon, size: 13).iconOnTextBaseline().foregroundStyle(muted ? Palette.muted : Palette.accent)
                Text(name)
                    .font(AppFont.captionSemibold)
                    .foregroundStyle(muted ? Palette.muted : Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s8)
                Text(estimate).font(AppFont.small).foregroundStyle(Palette.muted).lineLimit(1)
            }
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.line)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Palette.accent)
                            .frame(width: geometry.size.width * min(max(progress, 0), 1))
                    }
            }
            .frame(height: 4)
        }
    }
}
