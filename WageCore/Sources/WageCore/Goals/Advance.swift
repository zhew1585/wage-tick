import Foundation

/// 推进到此刻 (issue #1 Implementation Decisions)：处理随时间发生的状态变化。
/// 目前只有累计中目标达成：累计额达到目标金额时记录完成时间并冻结 (PRD 4.5.2)。
/// 完成时间取推进时的此刻；激活下一个目标、结转零头留给目标队列 (#12)。
func advance(_ state: AppState, now: Moment) -> AppState {
    guard let profile = state.profile, let current = state.accumulatingGoal else { return state }
    let income = Ledger.cumulativeIncome(profile: profile, today: Today(profile: profile, now: now))
    guard income - current.baseline >= current.goal.amount else { return state }
    var next = state
    next.goals[current.index].status = .completed(at: now.date)
    return next
}
