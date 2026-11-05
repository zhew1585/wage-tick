import Foundation

extension DayPlan {
    /// 当日计划 (PRD 4.3.2)：作息经半天假调整后的结果；全天请假没有计划，返回 nil。
    /// 半天假以午休为分界：上午假计划上班改为午休结束，下午假计划下班改为午休开始；
    /// 关闭午休时以计划上下班中点为分界 (4.4.2 #2、4.3.5 #20)。
    /// 半天假只剩一段工时，不再经过午休中 (4.3.3)。
    init?(schedule: WorkSchedule, leave: LeavePeriod?, on day: LocalDate, now: Moment) {
        let full = DayPlan(schedule: schedule, on: day, now: now)
        let midpoint = full.start.addingTimeInterval(full.end.timeIntervalSince(full.start) / 2)
        let boundary = full.lunch ?? Period(start: midpoint, end: midpoint)
        switch leave {
        case nil: self = full
        case .fullDay: return nil
        case .morning: self.init(start: boundary.end, end: full.end, lunch: nil)
        case .afternoon: self.init(start: full.start, end: boundary.start, lunch: nil)
        }
    }

    private init(start: Date, end: Date, lunch: Period?) {
        self.start = start
        self.end = end
        self.lunch = lunch
    }
}
