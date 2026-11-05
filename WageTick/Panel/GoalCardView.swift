import SwiftUI
import WageCore

/// 面板目标区 (PRD F9)：文字和进度原样取自快照的 `GoalCard` 与 `GoalQueueSection`。
/// 队列为空时整张卡片可点，进入目标管理；有排队中目标时下方是「显示更多 (N)」或展开后的排队卡片与「收起」。
struct GoalCardView: View {
    let card: GoalCard
    /// 排队部分；没有排队中目标时为 nil，不显示「显示更多」(AC-GPRG-08)。
    let queue: GoalQueueSection?
    let openGoals: () -> Void
    /// 点「显示更多」或「收起」：发 `.toggleGoalQueueExpanded`，展开状态由核心记住【O3】。
    let toggleQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mainCard
            if let queue {
                ForEach(queue.queued, content: queuedCard)
                Button(queue.toggleTitle, action: toggleQueue)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var mainCard: some View {
        switch card {
        case .empty(let prompt):
            Button(action: openGoals) {
                Text(prompt)
                    .font(.callout)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .active(let goal):
            activeCard(goal)
        }
    }

    private func activeCard(_ goal: ActiveGoalCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.name).font(.callout.weight(.medium))
                Spacer()
                Text(goal.estimate).font(.caption).foregroundStyle(Palette.muted)
            }
            ProgressView(value: goal.progress)
            Text(goal.amountText)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
        }
        .padding(10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control))
    }

    /// 排队中目标：名称、「排队中 · 预计 M月D日」、目标金额，没有进度条。
    private func queuedCard(_ goal: QueuedGoalCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.name).font(.callout.weight(.medium))
                Spacer()
                Text(goal.estimate).font(.caption).foregroundStyle(Palette.muted)
            }
            Text(goal.amountText)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
        }
        .padding(10)
        .background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.control))
    }
}
