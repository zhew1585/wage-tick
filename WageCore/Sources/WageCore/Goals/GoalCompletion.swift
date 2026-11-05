import Foundation

// 目标达成 (PRD 4.5.2、4.6.3、F9)：累计中目标完成、记下待播放的庆祝动画、产生达成事件，都在 `completeReachedGoal` 这一处。
// 目前由推进到此刻 (`advance`) 调用；编辑目标金额后立即完成 (#12) 也应调它，
// 这样不论哪条路完成，通知和动画都只出现一次。

/// 累计中目标的累计额达到目标金额时完成它，否则原样返回。
/// - 记录完成时间 (取此刻) 并冻结 (PRD 4.5.2 不变量 3)。
/// - 把这个目标排进待播放的庆祝动画，面板开始播放时由 `.acknowledgeCelebration` 移除。
/// - 目标达成通知开着时产生达成事件，文案不含金额，老板路过模式下不变 (PRD 4.6.3)。
/// 一次只完成一个目标；激活下一个排队目标、结转零头留给目标队列 (#12)。
func completeReachedGoal(_ state: AppState, now: Moment, holidays: HolidayTable) -> (state: AppState, events: [DomainEvent]) {
    guard let profile = state.profile, let current = state.accumulatingGoal else { return (state, []) }
    let income = Ledger.cumulativeIncome(state: state, profile: profile, now: now, holidays: holidays)
    guard income - current.baseline >= current.goal.amount else { return (state, []) }
    var next = state
    next.goals[current.index].status = .completed(at: now.date)
    next.pendingCelebrations = state.pendingCelebrations.filter { $0 != current.goal.id } + [current.goal.id]
    guard state.settings.goalReachedNotification else { return (next, []) }
    return (next, [.goalReached(message: NotificationCopy.goalReached(name: current.goal.name))])
}

/// 面板开始播放 `goalID` 的庆祝动画时确认，之后不再播放；其余待播放的不受影响。
func acknowledgeCelebration(goalID: Int, state: AppState) -> AppState {
    var next = state
    next.pendingCelebrations = state.pendingCelebrations.filter { $0 != goalID }
    return next
}
