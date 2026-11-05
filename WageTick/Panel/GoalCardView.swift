import SwiftUI
import WageCore

/// 面板目标区 (PRD F9)：文字和进度原样取自快照的 `GoalCard`。
/// 队列为空时整张卡片可点，进入目标管理。
struct GoalCardView: View {
    let card: GoalCard
    let openGoals: () -> Void

    var body: some View {
        switch card {
        case .empty(let prompt):
            Button(action: openGoals) {
                Text(prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
                Text(goal.estimate).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: goal.progress)
            Text(goal.amountText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
