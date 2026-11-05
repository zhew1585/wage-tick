import Foundation

// 目标达成 (PRD 4.5.2、4.6.3、F9)：累计中目标完成、记下待播放的庆祝动画、产生达成事件，都在这一处。
// 推进到此刻 (`advance`) 和编辑目标金额后立即完成 (#12) 共用 `completeReachedGoal`，
// 所以不论哪条路完成，通知和动画都只出现一次。

/// 累计中目标的累计额达到目标金额时完成它，否则原样返回。
/// - 记录完成时间 (取此刻) 并冻结 (PRD 4.5.2 不变量 3)。
/// - 记下这个目标的庆祝动画待播放，面板播放后由 `.acknowledgeCelebration` 清掉。
/// - 目标达成通知开着时产生达成事件，文案不含金额，老板路过模式下不变 (PRD 4.6.3)。
/// 激活下一个排队目标、结转零头留给目标队列 (#12)。
func completeReachedGoal(_ state: AppState, now: Moment, holidays: HolidayTable) -> (state: AppState, events: [DomainEvent]) {
    guard let profile = state.profile, let current = state.accumulatingGoal else { return (state, []) }
    let income = Ledger.cumulativeIncome(state: state, profile: profile, now: now, holidays: holidays)
    guard income - current.baseline >= current.goal.amount else { return (state, []) }
    var next = state
    next.goals[current.index].status = .completed(at: now.date)
    next.pendingCelebration = current.goal.id
    guard state.settings.goalReachedNotification else { return (next, []) }
    return (next, [.goalReached(message: NotificationCopy.goalReached(name: current.goal.name))])
}

/// 面板播放完 `goalID` 的庆祝动画后确认，之后不再播放。
/// 确认的不是待播放的那个 (如面板播放期间下一个目标又达成了) 时不变。
func acknowledgeCelebration(goalID: Int, state: AppState) -> AppState {
    guard state.pendingCelebration == goalID else { return state }
    var next = state
    next.pendingCelebration = nil
    return next
}

/// 目标达成通知开关属于界面设置，引导前也能改。
func setGoalReachedNotification(_ enabled: Bool, state: AppState) -> AppState {
    var next = state
    next.settings.goalReachedNotification = enabled
    return next
}

extension NotificationCopy {
    /// 目标达成通知正文，如「🎉 目标「Switch 2」达成」。不含金额，老板路过模式下不变 (PRD 4.6.3)。
    static func goalReached(name: String) -> String {
        "🎉 目标「\(name)」达成"
    }
}
