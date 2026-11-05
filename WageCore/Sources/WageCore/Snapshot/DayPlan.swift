import Foundation

/// 应出勤日判定 (PRD 4.2.2)。
/// 本期只按双休：周六、周日不应出勤，其余应出勤；节假日与单日覆盖留给后续票。
enum AttendanceRule {
    static func isAttendanceDay(_ date: LocalDate) -> Bool {
        !date.isWeekend
    }

    static func attendanceDayCount(in month: YearMonth) -> Int {
        month.days.filter(isAttendanceDay).count
    }

    /// `day` 之后 (不含当天) 的第一个应出勤日；一年内都没有时为 nil。
    static func nextAttendanceDay(after day: LocalDate) -> LocalDate? {
        (1...366).lazy.map { day.adding(days: $0) }.first(where: isAttendanceDay)
    }
}

/// 当日计划落到绝对时刻上的样子 (PRD 4.3.2)，用来推导日状态与有效工时。
struct DayPlan {
    let start: Date
    let end: Date
    let lunch: (start: Date, end: Date)?

    /// 当日计划 = 作息 (本期没有半天假调整)。
    init(schedule: WorkSchedule, on day: LocalDate, now: Moment) {
        start = now.date(on: day, at: schedule.start)
        end = now.date(on: day, at: schedule.end)
        lunch = schedule.lunch.map { (now.date(on: day, at: $0.start), now.date(on: day, at: $0.end)) }
    }

    /// 日状态：到达计划上班即上班中，到达午休开始即午休中，到达计划下班即已下班 (PRD 4.3.3)。
    func status(at now: Date) -> DayStatus {
        if now < start { return .notStarted }
        if now >= end { return .offWork }
        if let lunch, now >= lunch.start, now < lunch.end { return .lunchBreak }
        return .working
    }

    /// 计入有效工时的时段：有午休时为上午、下午两段，关闭午休时为一整段。
    var workPeriods: [(start: Date, end: Date)] {
        guard let lunch else { return [(start, end)] }
        return [(start, lunch.start), (lunch.end, end)]
    }

    /// 应有有效工时 (毫秒)：计划上下班之间扣除午休；关闭午休时全部计入 (PRD 4.2.3 #4)。
    var effectiveMilliseconds: Int {
        elapsedMilliseconds(at: end)
    }

    /// 截至 `now` 已过的有效工时 (毫秒)，午休时段不计入。
    func elapsedMilliseconds(at now: Date) -> Int {
        let worked = Self.overlap(from: start, to: end, upTo: now)
        let rested = lunch.map { Self.overlap(from: $0.start, to: $0.end, upTo: now) } ?? 0
        return Int(((worked - rested) * 1000).rounded(.down))
    }

    /// 区间 [from, to) 中早于 `now` 的部分有多长 (秒)。
    private static func overlap(from: Date, to: Date, upTo now: Date) -> TimeInterval {
        max(0, min(to, now).timeIntervalSince(from))
    }
}
