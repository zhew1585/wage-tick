import Foundation

/// 当月工资换算 (设计稿 P1 引导 · 2 作息「按这个作息算」)：本月上班日、满勤日薪、标准工时、时薪。
/// 文字已按 D9 格式化好 (PRD 4.7.1 第 5 条)，外壳原样展示。
/// 引导里拿完成引导的试算快照 (`dryRun(.completeOnboarding(...))`) 读它，跟着输入走。
public struct WageRates: Sendable, Equatable {
    /// 「本月上班日」，如「21 天」：当月应出勤日数 (PRD 4.2.2)。
    public let attendanceDays: StatItem
    /// 「满勤日薪」，如「¥952.381」：当月日薪 (PRD 4.2.4)。
    public let dailyWage: StatItem
    /// 「标准工时」，如「8 小时」「7.5 小时」：今天生效作息的标准工时 (PRD 4.2.3)，保留 1 位小数，与面板工作进度一致。
    public let standardHours: StatItem
    /// 「时薪」，如「¥119.0476」：日薪 ÷ 标准工时 (PRD 4.2.4)。
    public let hourlyWage: StatItem
}

extension Snapshot {
    /// 本月的工资换算；未完成引导时为 nil。每次调用都现算，只给引导这类不在刷新热路径上的地方用。
    public var wageRates: WageRates? {
        guard let history else { return nil }
        let month = history.today.date.yearMonth
        let days = AttendanceRule(holidays: history.holidays).attendanceDayCount(in: month)
        let wage = history.today.dailyWage
        let schedule = history.profile.schedule(on: history.today.date)
        let milliseconds = schedule.standardMilliseconds
        return WageRates(
            attendanceDays: StatItem(title: "本月上班日", value: "\(days) 天"),
            dailyWage: StatItem(title: "满勤日薪", value: Format.money(wage)),
            standardHours: StatItem(title: "标准工时", value: "\(Format.workHours(milliseconds: milliseconds)) 小时"),
            // 时薪 = 日薪 × 1 小时 ÷ 标准工时，与白干倒贴同一公式 (`WorkSchedule.owed`)；校验保证标准工时大于 0。
            hourlyWage: StatItem(title: "时薪", value: Format.money(schedule.owed(dailyWage: wage, milliseconds: 3_600_000)))
        )
    }
}
