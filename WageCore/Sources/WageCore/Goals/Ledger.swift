import Foundation

/// 跨月的收入汇总：目标用的累计收入 (PRD 4.5.1)。
enum Ledger {
    /// 累计收入 = 安装当月起所有已结算应出勤日的结算之和 + 今日已赚。
    /// 每天的结算取自 `DaySettlement` (今日上限，已扣掉当日扣款)；安装日之前已过的应出勤日没有日记录，天然按满勤结算 (PRD 4.1.1)。
    /// 系统时间被拨回到安装当月之前时 (PRD 4.3.5 #11) 没有任何可计入的日子，为 0。
    static func cumulativeIncome(profile: Profile, dayRecords: [DayRecord], today: Today, holidays: HolidayTable) -> Decimal {
        let firstMonth = profile.installDate.yearMonth
        guard today.date.yearMonth >= firstMonth else { return 0 }
        let rule = AttendanceRule(holidays: holidays)
        let records = Dictionary(dayRecords.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var total = today.earnings?.earned ?? 0
        var month = firstMonth
        while month <= today.date.yearMonth {
            let wage = DaySettlement.dailyWage(profile: profile, month: month, rule: rule)
            for day in month.days where day < today.date && rule.isAttendanceDay(day) {
                total += DaySettlement(dailyWage: wage, record: records[day]).cap
            }
            month = month.next
        }
        return total
    }
}

extension YearMonth {
    /// 下一个月。
    var next: YearMonth {
        month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1)
    }
}

extension Ledger {
    /// 命令里用的累计收入：按此刻推导今天，再汇总。
    static func cumulativeIncome(state: AppState, profile: Profile, now: Moment, holidays: HolidayTable) -> Decimal {
        let today = Today(profile: profile, dayRecords: state.dayRecords, now: now, holidays: holidays)
        return cumulativeIncome(profile: profile, dayRecords: state.dayRecords, today: today, holidays: holidays)
    }
}
