import Foundation

/// 白干段的计时推导 (PRD 4.4.3 #3)：计时中的段算到此刻，最晚算到自动停止时刻。
/// 白干段记在开始那天的日记录里，可以跨过零点，整段时长与倒贴都算在开始那天。
/// 面板、历史、推进到此刻、补记与修改共用这一套，口径一致。
struct UnpaidWorkClock {
    let profile: Profile
    let rule: AttendanceRule
    /// 找下一个应出勤日的请假用。
    let dayRecords: [DayRecord]
    let now: Moment

    /// 找下一次计划上班时最多往后看多少天。
    static let lookaheadDays = 60
    /// 往后 `lookaheadDays` 天都没有要上班的日子时 (如全部改成不上班)，在开始那天之后第几天的 0 点自动停止。
    static let fallbackDays = 7

    init(profile: Profile, rule: AttendanceRule, dayRecords: [DayRecord], now: Moment) {
        self.profile = profile
        self.rule = rule
        self.dayRecords = dayRecords
        self.now = now
    }

    /// `holidays` 须已并入单日覆盖与休息模式 (见 `HolidayTable.overlaying(_:)`)。
    init(profile: Profile, holidays: HolidayTable, dayRecords: [DayRecord], now: Moment) {
        self.init(profile: profile, rule: AttendanceRule(holidays: holidays), dayRecords: dayRecords, now: now)
    }

    /// `day` 开始的白干的自动停止时刻 (PRD 参数表「白干自动停止时刻」)：`day` 之后第一个应出勤日的计划上班，
    /// 按那天生效的作息与请假后的当日计划 (开头请了假就是请假后实际开始上班的时刻)；全天请假的日子跳过，接着往后找。
    /// 往后 60 天都找不到时为 `day` 之后第 7 天的 0 点。按此刻所在时区落到绝对时刻 (PRD 4.3.5 #11)。
    func autoStop(after day: LocalDate) -> Date {
        for offset in 1...Self.lookaheadDays {
            let date = day.adding(days: offset)
            guard rule.isAttendanceDay(date) else { continue }
            let leave = dayRecords.first { $0.date == date }?.leave?.range
            if let plan = DayPlan(schedule: profile.schedule(on: date), leave: leave, on: date, now: now) {
                return plan.start
            }
        }
        return now.date(on: day.adding(days: Self.fallbackDays), at: TimeOfDay(hour: 0, minute: 0))
    }

    /// 这段白干推导出的结束时刻：结束了的取结束时刻，计时中的取此刻，最晚到自动停止时刻。`day` 是它所在的日子。
    func end(of segment: UnpaidWorkSegment, on day: LocalDate) -> Date {
        segment.end ?? min(now.date, autoStop(after: day))
    }

    /// 此刻是否还在计时：没结束，且还没到自动停止时刻。
    func isRunning(_ segment: UnpaidWorkSegment, on day: LocalDate) -> Bool {
        segment.end == nil && now.date < autoStop(after: day)
    }

    /// 可能忘了停 (PRD 4.3.5 #12)：已被自动停止，或该停了还没推进。
    func isAutoStopped(_ segment: UnpaidWorkSegment, on day: LocalDate) -> Bool {
        segment.autoStopped || (segment.end == nil && !isRunning(segment, on: day))
    }

    /// 这段白干的时长 (毫秒)，与 `advance` 自动停止的结果一致；结束早于开始的段按 0 计。
    func milliseconds(_ segment: UnpaidWorkSegment, on day: LocalDate) -> Int {
        max(0, Int((end(of: segment, on: day).timeIntervalSince(segment.start) * 1000).rounded(.down)))
    }

    /// 某天各段白干的时长之和 (毫秒)。
    func milliseconds(_ segments: [UnpaidWorkSegment], on day: LocalDate) -> Int {
        segments.map { milliseconds($0, on: day) }.reduce(0, +)
    }

    /// 某天白干 `milliseconds` 毫秒倒贴的钱 = 时长 × 时薪 (PRD 4.4.3 #4)，时薪按那天所在月的日薪与那天生效的作息。
    func owed(on day: LocalDate, milliseconds: Int) -> Decimal {
        profile.schedule(on: day).owed(dailyWage: rule.dailyWage(in: day.yearMonth, profile: profile), milliseconds: milliseconds)
    }
}
