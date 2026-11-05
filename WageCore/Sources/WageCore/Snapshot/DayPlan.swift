import Foundation

/// 应出勤日判定 (PRD 4.2.2)，先命中者为准：调休上班日 > 法定节假日 > 周六日 > 其余应出勤。
/// 单日覆盖留给后续票。节假日表里没有的年份 (含缺失年份) 自然落到按双休判定。
struct AttendanceRule {
    let holidays: HolidayTable

    func isAttendanceDay(_ date: LocalDate) -> Bool {
        switch holidays.kind(on: date) {
        case .makeupDay: true
        case .holiday: false
        case nil: !date.isWeekend
        }
    }

    func attendanceDayCount(in month: YearMonth) -> Int {
        month.days.filter(isAttendanceDay).count
    }

    /// 找下一个应出勤日时最多往后看多少天。
    private static let lookaheadDays = 366

    /// `day` 之后 (不含当天) 的第一个应出勤日；一年内都没有时为 nil。
    func nextAttendanceDay(after day: LocalDate) -> LocalDate? {
        (1...Self.lookaheadDays).lazy.map { day.adding(days: $0) }.first(where: isAttendanceDay)
    }
}

/// 一段绝对时间 [start, end)。
struct Period: Sendable, Equatable {
    let start: Date
    let end: Date

    var length: TimeInterval { end.timeIntervalSince(start) }
}

/// 当日计划落到绝对时刻上的样子 (PRD 4.3.2)，用来推导日状态与有效工时。
struct DayPlan: Sendable, Equatable {
    let start: Date
    let end: Date
    let lunch: Period?

    /// 作息原样落到这一天；按半天假调整见 `init(schedule:leave:on:now:)`。
    init(schedule: WorkSchedule, on day: LocalDate, now: Moment) {
        start = now.date(on: day, at: schedule.start)
        end = now.date(on: day, at: schedule.end)
        lunch = schedule.lunch.map { Period(start: now.date(on: day, at: $0.start), end: now.date(on: day, at: $0.end)) }
    }

    /// 日状态：到达计划上班即上班中，到达午休开始即午休中，到达计划下班即已下班 (PRD 4.3.3)。
    func status(at now: Date) -> DayStatus {
        if now < start { return .notStarted }
        if now >= end { return .offWork }
        if let lunch, now >= lunch.start, now < lunch.end { return .lunchBreak }
        return .working
    }

    /// 计入有效工时的时段：有午休时为上午、下午两段，关闭午休时为一整段。
    /// 没有时长的段不算 (午休紧贴计划上班或下班，或半天假后那半天没有工时)。
    var workPeriods: [Period] {
        let periods = lunch.map { [Period(start: start, end: $0.start), Period(start: $0.end, end: end)] }
            ?? [Period(start: start, end: end)]
        return periods.filter { $0.length > 0 }
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
