import Foundation

/// 跨月的收入汇总：目标用的累计收入 (PRD 4.5.1)。
enum Ledger {
    /// 累计收入 = 安装当月起所有已结算应出勤日的结算之和 + 今日已赚。
    /// 安装日之前已过的应出勤日没有日记录，天然按满勤结算 (PRD 4.1.1)。
    /// 系统时间被拨回到安装当月之前时 (PRD 4.3.5 #11) 没有任何可计入的日子，为 0。
    static func cumulativeIncome(profile: Profile, today: Today) -> Decimal {
        let firstMonth = profile.installDate.yearMonth
        guard today.date.yearMonth >= firstMonth else { return 0 }
        var total = today.earnings?.earned ?? 0
        var month = firstMonth
        while month <= today.date.yearMonth {
            let wage = dailyWage(profile: profile, month: month)
            for day in month.days where day < today.date && AttendanceRule.isAttendanceDay(day) {
                total += settlement(of: day, dailyWage: wage)
            }
            month = month.next
        }
        return total
    }

    /// 某个已过应出勤日的结算 (PRD 4.3.4)。
    /// 本期还没有扣款和请假，结算 = 日薪；接入后改为该日今日上限。
    static func settlement(of day: LocalDate, dailyWage: Decimal) -> Decimal {
        dailyWage
    }

    /// 当月日薪 = 当月月薪 ÷ 当月应出勤日数 (PRD 4.2.4)。
    private static func dailyWage(profile: Profile, month: YearMonth) -> Decimal {
        profile.salary(for: month) / Decimal(AttendanceRule.attendanceDayCount(in: month))
    }
}

extension YearMonth {
    /// 下一个月。
    var next: YearMonth {
        month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1)
    }
}
