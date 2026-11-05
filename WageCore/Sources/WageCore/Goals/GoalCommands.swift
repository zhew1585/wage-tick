import Foundation

/// 新建目标 (PRD 4.5.2)：队列为空时直接成为累计中，起算基准 = 此刻累计收入，不追溯之前赚的钱；
/// 已有累计中目标时排到队尾，状态为排队中。
func createGoal(
    name: String,
    amount: Decimal,
    state: AppState,
    now: Moment,
    holidays: HolidayTable
) throws(CommandError) -> AppState {
    guard let profile = state.profile else { throw .notOnboarded }
    if let error = Validation.goal(name: name, amount: amount) { throw error }
    let status: GoalStatus = state.accumulatingGoal == nil
        ? .accumulating(baseline: Ledger.cumulativeIncome(state: state, profile: profile, now: now, holidays: holidays))
        : .queued
    var next = state
    next.goals.append(Goal(
        id: (state.goals.map(\.id).max() ?? 0) + 1,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        amount: amount,
        status: status
    ))
    return next
}

extension AppState {
    /// 累计中目标及其起算基准；同一时间最多一个 (PRD 4.5.2 不变量 1)。
    var accumulatingGoal: (index: Int, goal: Goal, baseline: Decimal)? {
        for (index, goal) in goals.enumerated() {
            if case .accumulating(let baseline) = goal.status { return (index, goal, baseline) }
        }
        return nil
    }
}
