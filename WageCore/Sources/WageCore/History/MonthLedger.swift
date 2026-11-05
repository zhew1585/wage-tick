import Foundation

/// 某个月逐日推导的结果，月汇总与月日历都从这里取 (PRD 4.6.1)。
/// 结算统一用 `DaySettlement`，与今天的今日上限、本月累计同一套推导。
struct MonthLedger {
    let month: YearMonth
    /// 当月日薪，见 `AttendanceRule.dailyWage(in:profile:)`。
    let dailyWage: Decimal
    let days: [DayLedger]

    var attendanceDayCount: Int { days.filter(\.isAttendanceDay).count }
}

/// 某一天推导出的事实。
struct DayLedger {
    let date: LocalDate
    let source: AttendanceSource
    let isAttendanceDay: Bool
    let record: DayRecord?
    /// 应出勤日的结算推导；不应出勤的日子为 nil，没有收入。
    let settlement: DaySettlement?
    /// 这天的白干段，连同各段时长，按开始时刻先后。
    let unpaidWork: [TimedSegment]

    var unpaidWorkMilliseconds: Int { unpaidWork.map(\.milliseconds).reduce(0, +) }

    /// 请假天数：全天计 1，半天计 0.5 (PRD 4.6.1)；不应出勤的日子不算。
    var leaveDays: Decimal {
        guard isAttendanceDay, let leave = record?.leave else { return 0 }
        return leave.period == .fullDay ? 1 : Decimal(string: "0.5")!
    }
}

/// 一段白干与它推导出的时长 (毫秒)，计时中的那段算到此刻。
struct TimedSegment {
    let segment: UnpaidWorkSegment
    let milliseconds: Int
}

extension HistoryLedger {
    /// 逐日推导一个月。
    func monthLedger(for month: YearMonth) -> MonthLedger {
        let wage = rule.dailyWage(in: month, profile: inputs.profile)
        let days = month.days.map { date in
            let record = records[date]
            let isAttendance = rule.isAttendanceDay(date)
            return DayLedger(
                date: date,
                source: rule.source(on: date),
                isAttendanceDay: isAttendance,
                record: record,
                settlement: isAttendance ? DaySettlement(dailyWage: wage, record: record) : nil,
                unpaidWork: (record?.unpaidWork ?? []).map {
                    TimedSegment(segment: $0, milliseconds: $0.milliseconds(on: date, now: inputs.now))
                }
            )
        }
        return MonthLedger(month: month, dailyWage: wage, days: days)
    }

    /// 月汇总 (PRD 4.6.1)：结算总额、应出勤日数、扣款合计、请假天数、白干时长合计。
    /// 结算总额 = 当月各应出勤日结算之和；本月直接取本月累计 (今天之前的结算 + 今日已赚)。
    /// 扣款、请假、白干与结算总额同口径，只算到今天 (PRD 4.3.4「未来日子不计入」)；过去的月份即整月。
    func summary(_ ledger: MonthLedger) -> HistoryMonthSummary {
        let month = ledger.month
        let isCurrent = month == today.yearMonth
        let happened = ledger.days.filter { $0.date <= today }
        let settled = isCurrent
            ? inputs.today.monthToDate
            : happened.compactMap(\.settlement).map(\.cap).reduce(0, +)
        let deducted = happened.compactMap(\.settlement).map(\.deductionTotal).reduce(0, +)
        let leaveDays = happened.map(\.leaveDays).reduce(0, +)
        let unpaid = happened.map(\.unpaidWorkMilliseconds).reduce(0, +)
        return HistoryMonthSummary(
            month: month,
            title: "\(month.year)年\(month.month)月",
            isCurrentMonth: isCurrent,
            stats: [
                StatItem(title: "结算总额", value: Format.money(settled)),
                StatItem(title: "应出勤日数", value: "\(ledger.attendanceDayCount) 天"),
                StatItem(title: "扣款合计", value: Format.deductionOrZero(deducted)),
                StatItem(title: "请假天数", value: "\(Format.trimmed(leaveDays)) 天"),
                StatItem(title: "白干时长", value: Format.hoursMinutes(milliseconds: unpaid)),
            ]
        )
    }
}

extension Format {
    /// 扣款合计：有扣款时如「−¥550」，没有时为「¥0」，不出现「−¥0」。
    static func deductionOrZero(_ amount: Decimal) -> String {
        amount > 0 ? deduction(amount) : money(0)
    }
}
