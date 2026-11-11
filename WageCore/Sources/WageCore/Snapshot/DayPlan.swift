import Foundation

/// 应出勤日判定 (PRD 4.2.2)，先命中者为准：单日覆盖 > 调休上班日 > 法定节假日 > 休息模式 > 其余应出勤。
/// 单日覆盖与各月的休息模式随节假日表传入 (见 `HolidayTable.overlaying(_:)`)。
/// 节假日表里没有的年份 (含缺失年份) 自然落到按休息模式判定。
struct AttendanceRule: Sendable, Equatable {
    let holidays: HolidayTable

    func isAttendanceDay(_ date: LocalDate) -> Bool {
        if let override = holidays.overrides[date] { return override.isAttendanceDay }
        return switch holidays.kind(on: date) {
        case .makeupDay: true
        case .holiday: false
        case nil: !holidays.restMode(for: date.yearMonth).isRestDay(date)
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
    /// 落在中间的请假 (PRD 4.4.2)：一天分成前后两段上班，期间为请假中；没有时为 nil。
    let leave: Period?

    /// 作息原样落到这一天；按请假调整见 `init(schedule:leave:on:now:)`。
    init(schedule: WorkSchedule, on day: LocalDate, now: Moment) {
        start = now.date(on: day, at: schedule.start)
        end = now.date(on: day, at: schedule.end)
        lunch = schedule.lunch.map { Period(start: now.date(on: day, at: $0.start), end: now.date(on: day, at: $0.end)) }
        leave = nil
    }

    init(start: Date, end: Date, lunch: Period?, leave: Period?) {
        self.start = start
        self.end = end
        self.lunch = lunch
        self.leave = leave
    }

    /// 日状态：到达计划上班即上班中，落在中间的请假里为请假中 (优先于饭点)，到达饭点开始即干饭中，
    /// 到达计划下班即已下班 (PRD 4.3.3)。
    func status(at now: Date) -> DayStatus {
        if now < start { return .notStarted }
        if now >= end { return .offWork }
        if let leave, now >= leave.start, now < leave.end { return .onLeave }
        if let lunch, now >= lunch.start, now < lunch.end { return .lunchBreak }
        return .working
    }

    /// 计入有效工时的时段：计划上下班之间去掉饭点与请假，按先后排列。
    /// 没有时长的段不算 (饭点紧贴计划上班或下班)。
    var workPeriods: [Period] {
        let gaps = [lunch, leave].compactMap { $0 }.sorted { $0.start < $1.start }
        var periods: [Period] = []
        var cursor = start
        for gap in gaps {
            periods.append(Period(start: cursor, end: min(gap.start, end)))
            cursor = max(cursor, gap.end)
        }
        periods.append(Period(start: cursor, end: end))
        return periods.filter { $0.length > 0 }
    }

    /// 应有有效工时 (毫秒)：计划上下班之间扣除饭点与请假；关闭饭点时全部计入 (PRD 4.2.3 #4)。
    var effectiveMilliseconds: Int {
        elapsedMilliseconds(at: end)
    }

    /// 截至 `now` 已过的有效工时 (毫秒)，饭点、请假时段不计入。
    func elapsedMilliseconds(at now: Date) -> Int {
        let seconds = workPeriods.map { max(0, min($0.end, now).timeIntervalSince($0.start)) }.reduce(0, +)
        return Int((seconds * 1000).rounded(.down))
    }
}
