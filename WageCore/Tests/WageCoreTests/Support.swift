import Foundation
import WageCore

// 测试共用的时钟与算例数据。
// 标准算例 (PRD 4.2.4) 落在 2026 年 2 月：只按双休时该月正好 20 个应出勤日。

let shanghai = TimeZone(identifier: "Asia/Shanghai")!

/// 构造上海时区的某个此刻。
func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Moment {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = shanghai
    let date = calendar.date(from: DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute, second: second
    ))!
    return Moment(date: date, timeZone: shanghai)
}

/// 2026-02-11 (周三) 的某个时刻，标准算例里的"今天"。
func standardDay(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Moment {
    moment(2026, 2, 11, hour, minute, second)
}

/// 标准算例作息：10:00 至 18:00，饭点 12:00 至 13:00。
let standardSchedule = WorkSchedule(
    start: TimeOfDay(hour: 10, minute: 0),
    end: TimeOfDay(hour: 18, minute: 0),
    lunch: LunchBreak(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 13, minute: 0))
)

/// 在 `at` 时刻按给定月薪、作息与休息模式完成引导后的状态。
func onboarded(
    salary: Decimal = 20000,
    schedule: WorkSchedule = standardSchedule,
    restMode: RestModeChoice = .twoDaysOff,
    at now: Moment = moment(2026, 2, 11, 9, 0)
) throws -> AppState {
    let command = Command.completeOnboarding(
        OnboardingInput(monthlySalary: salary, schedule: schedule, restMode: restMode, launchAtLogin: true)
    )
    return try apply(command, to: AppState(), at: now).state
}

/// 测试侧四舍五入到 4 位小数，用于和 PRD 算例里的 4 位数字比对。
func rounded4(_ value: Decimal) -> Decimal {
    var input = value
    var result = Decimal()
    NSDecimalRound(&result, &input, 4, .plain)
    return result
}
