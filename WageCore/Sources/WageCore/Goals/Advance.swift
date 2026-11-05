import Foundation

/// 推进到此刻 (issue #1 Implementation Decisions)：依次处理随时间发生的状态变化，事件汇总返回。
/// 1. 白干到 23:59:59 自动停止 (#9)
/// 2. 累计中目标达成 (见 `completeReachedGoal`，#13)
/// 3. 跨过当日计划下班 (#10)
func advance(_ state: AppState, now: Moment, holidays: HolidayTable) -> (state: AppState, events: [DomainEvent]) {
    let stopped = advanceUnpaidWork(state: state, now: now)
    let goals = completeReachedGoal(stopped, now: now, holidays: holidays)
    let offWork = advanceOffWork(goals.state, now: now, holidays: holidays)
    return (offWork.state, goals.events + offWork.events)
}

