import Foundation

/// 推进到此刻 (issue #1 Implementation Decisions)：依次处理随时间发生的状态变化，事件汇总返回。
/// 1. 白干到 23:59:59 自动停止 (#9)
/// 2. 累计中目标达成
/// 3. 跨过当日计划下班 (#10)
func advance(_ state: AppState, now: Moment, holidays: HolidayTable) -> (state: AppState, events: [DomainEvent]) {
    let stopped = advanceUnpaidWork(state: state, now: now)
    let goals = advanceGoals(stopped, now: now, holidays: holidays)
    let offWork = advanceOffWork(goals.state, now: now, holidays: holidays)
    return (offWork.state, goals.events + offWork.events)
}

/// 累计额达到目标金额时完成并冻结，激活下一个排队目标、结转零头 (PRD 4.5.2)，完成时间取推进时的此刻。
/// 与编辑、删除共用同一入口 `completingReachedGoals`，达成事件 (#13) 也从那里来。
private func advanceGoals(_ state: AppState, now: Moment, holidays: HolidayTable) -> (state: AppState, events: [DomainEvent]) {
    completingReachedGoals(state, now: now, holidays: holidays)
}
