import Foundation

/// 距发薪 (issue #20，GLOSSARY)：今天到下一个实际发薪日 (按 `PaydayShift` 挪过之后) 的自然日天数，
/// 以及发薪周期进度。概览页脚、菜单栏菜单与桌面悬浮小牛 (#21) 共用。
public struct PaydayCountdown: Sendable, Equatable {
    /// 今天就是发薪日时为 0，明天为 1。
    public let days: Int
    /// 下一个实际发薪日；今天发薪时就是今天。
    public let next: LocalDate
    /// 上一个实际发薪日 (早于 `next`)，发薪周期的起点。
    public let previous: LocalDate

    /// 发薪周期进度，0 至 1：上一个发薪日为 0，发薪当天为 1。页脚进度条、存钱罐据此填充。
    public var progress: Decimal {
        let length = next.days(since: previous)
        return Decimal(length - days) / Decimal(length)
    }
}

extension AttendanceRule {
    /// 从 `day` 起的距发薪：在前后两个月的实际发薪日里找第一个不早于今天的，以及它前面那个。
    /// 挪动最多一个月左右，前后各看两个月足够覆盖跨月提前或顺延。
    func paydayCountdown(from day: LocalDate, payday: Payday) -> PaydayCountdown {
        let months = (-2...2).map { day.yearMonth.adding(months: $0) }
        let dates = months.map { actualPayday(in: $0, payday: payday) }.sorted()
        // 两个月之后的发薪日一定晚于今天，`first` 必有值；`next` 不是最早的那个，`last` 也必有值。
        let next = dates.first { $0 >= day }!
        let previous = dates.last { $0 < next }!
        return PaydayCountdown(days: next.days(since: day), next: next, previous: previous)
    }

    /// 某月的实际发薪日：几号超过当月天数时取月末；那天不应出勤时按 `shift` 往前或往后找最近的应出勤日，
    /// 一个月内都找不到 (整月被单日覆盖成不上班) 时不挪。
    func actualPayday(in month: YearMonth, payday: Payday) -> LocalDate {
        let days = month.days
        let nominal = days[min(payday.dayOfMonth, days.count) - 1]
        let step: Int
        switch payday.shift {
        case .unchanged: return nominal
        case .earlier: step = -1
        case .later: step = 1
        }
        guard !isAttendanceDay(nominal) else { return nominal }
        return (1...31).lazy.map { nominal.adding(days: $0 * step) }.first(where: isAttendanceDay) ?? nominal
    }
}

extension YearMonth {
    /// 往后数 `months` 个月，负数往前 (公元后的年份，月序号不会为负)。
    func adding(months: Int) -> YearMonth {
        let index = year * 12 + (month - 1) + months
        return YearMonth(year: index / 12, month: index % 12 + 1)
    }
}
