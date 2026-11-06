import Foundation

/// 小组件时间线上的一条：到 `date` 这一刻起显示 `snapshot`，直到下一条。
public struct WidgetEntry: Sendable, Equatable {
    public let date: Date
    public let snapshot: WidgetSnapshot

    public init(date: Date, snapshot: WidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

/// 小组件时间线默认往后排多久 (PRD F14)：排完后系统再来要下一段。
public let widgetTimelineHorizon: TimeInterval = 60 * 60

/// 核心入口三：桌面小组件 (PRD F14) 从 `now` 起的时间线，纯函数，不改状态。
/// 第一条在 `now`，之后每个整分钟一条，直到 `now + horizon`；日状态切换的时刻 (计划上班、饭点、请假、计划下班、零点)
/// 另有一条 (都落在整分钟上，与整分钟那条合并)。数字因此约每分钟更新一次，倒计时与白干计时由外壳的计时文字实时走。
/// 每条都先在那一刻推进到此刻 (白干自动停止、目标达成)，再取快照，与 App 每次刷新的做法相同。
public func widgetTimeline(
    of state: AppState, from now: Moment, holidays: HolidayTable = .empty, horizon: TimeInterval = widgetTimelineHorizon
) -> [WidgetEntry] {
    widgetMoments(of: state, from: now, holidays: holidays, horizon: horizon).map { date in
        let moment = Moment(date: date, timeZone: now.timeZone)
        return WidgetEntry(date: date, snapshot: widgetSnapshot(of: state, at: moment, holidays: holidays))
    }
}

/// 小组件在 `now` 这一刻的内容：先推进到此刻，再取快照。
public func widgetSnapshot(of state: AppState, at now: Moment, holidays: HolidayTable = .empty) -> WidgetSnapshot {
    // 推进到此刻没有校验，不会被拒；万一被拒就按原状态取快照。
    let advanced = (try? apply(.advance, to: state, at: now, holidays: holidays).state) ?? state
    return WidgetSnapshot(snapshot: snapshot(of: advanced, at: now, holidays: holidays), now: now)
}

/// 时间线各条的时刻，升序、不重复。
func widgetMoments(of state: AppState, from now: Moment, holidays: HolidayTable, horizon: TimeInterval) -> [Date] {
    let end = now.date.addingTimeInterval(horizon)
    let firstMinute = (now.date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60
    let minutes = stride(from: firstMinute, through: end.timeIntervalSinceReferenceDate, by: 60)
        .map { Date(timeIntervalSinceReferenceDate: $0) }
    let boundaries = statusBoundaries(of: state, at: now, holidays: holidays).filter { $0 > now.date && $0 <= end }
    return Array(Set([now.date] + minutes + boundaries)).sorted()
}

/// 今天日状态会切换的时刻：当日计划的上班、饭点起止、请假起止、下班，以及明天零点。
private func statusBoundaries(of state: AppState, at now: Moment, holidays: HolidayTable) -> [Date] {
    let midnight = now.date(on: now.localDate.adding(days: 1), at: TimeOfDay(hour: 0, minute: 0))
    guard let plan = snapshot(of: state, at: now, holidays: holidays).today?.plan else { return [midnight] }
    let gaps = [plan.lunch, plan.leave].compactMap { $0 }.flatMap { [$0.start, $0.end] }
    return [plan.start, plan.end, midnight] + gaps
}
