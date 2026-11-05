import Foundation

extension DayPlan {
    /// 当日计划 (PRD 4.3.2)：作息经半天假调整后的结果；全天请假没有计划，返回 nil。
    /// 半天假以午休为分界：上午假计划上班改为午休结束，下午假计划下班改为午休开始；
    /// 关闭午休时以计划上下班中点为分界 (4.4.2 #2、4.3.5 #20)。
    /// 半天假只剩一段工时，不再经过午休中 (4.3.3)。
    init?(schedule: WorkSchedule, leave: LeavePeriod?, on day: LocalDate, now: Moment) {
        let full = DayPlan(schedule: schedule, on: day, now: now)
        let boundary = full.halfDayBoundary
        switch leave {
        case nil: self = full
        case .fullDay: return nil
        case .morning: self.init(start: boundary.end, end: full.end, lunch: nil)
        case .afternoon: self.init(start: full.start, end: boundary.start, lunch: nil)
        }
    }

    /// 请某个时段的假请掉的那段时间 [start, end)：全天为计划上下班，上午到分界开始，下午从分界结束。
    /// 分界同 `init(schedule:leave:on:now:)`。
    static func leaveSpan(_ period: LeavePeriod, schedule: WorkSchedule, on day: LocalDate, now: Moment) -> Period {
        let full = DayPlan(schedule: schedule, on: day, now: now)
        let boundary = full.halfDayBoundary
        return switch period {
        case .fullDay: Period(start: full.start, end: full.end)
        case .morning: Period(start: full.start, end: boundary.start)
        case .afternoon: Period(start: boundary.end, end: full.end)
        }
    }

    /// 半天假的分界：有午休时为午休，关闭午休时为计划上下班的中点 (长度为 0)。
    private var halfDayBoundary: Period {
        let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
        return lunch ?? Period(start: midpoint, end: midpoint)
    }

    private init(start: Date, end: Date, lunch: Period?) {
        self.start = start
        self.end = end
        self.lunch = lunch
    }
}
