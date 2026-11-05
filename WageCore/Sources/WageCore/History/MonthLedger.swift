import Foundation

/// 某个月逐日推导的结果，月汇总与月日历都从这里取 (PRD 4.6.1)。
/// 结算统一用 `DaySettlement`，与今天的今日上限、本月累计同一套推导。
struct MonthLedger {
    let month: YearMonth
    /// 当月日薪 = 当月月薪 ÷ 当月应出勤日数 (PRD 4.2.4)；应出勤日数为 0 时没有日薪，记 0 (PRD 4.3.5 #19)。
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
    /// 这天各白干段的时长 (毫秒)，与白干段一一对应；计时中的那段算到此刻。
    let unpaidWork: [Int]

    var unpaidWorkMilliseconds: Int { unpaidWork.reduce(0, +) }

    /// 请假天数：全天计 1，半天计 0.5 (PRD 4.6.1)；不应出勤的日子不算。
    var leaveDays: Decimal {
        guard isAttendanceDay, let leave = record?.leave else { return 0 }
        return leave.period == .fullDay ? 1 : Decimal(string: "0.5")!
    }
}

extension HistoryLedger {
    /// 逐日推导一个月。
    func ledger(for month: YearMonth) -> MonthLedger {
        let dates = month.days
        let facts = dates.map { (date: $0, source: rule.source(on: $0), isAttendance: rule.isAttendanceDay($0)) }
        let count = facts.filter(\.isAttendance).count
        let wage = count > 0 ? source.profile.salary(for: month) / Decimal(count) : 0
        let days = facts.map { fact in
            let record = records[fact.date]
            return DayLedger(
                date: fact.date,
                source: fact.source,
                isAttendanceDay: fact.isAttendance,
                record: record,
                settlement: fact.isAttendance ? DaySettlement(dailyWage: wage, record: record) : nil,
                unpaidWork: (record?.unpaidWork ?? []).map { $0.milliseconds(on: fact.date, now: source.now) }
            )
        }
        return MonthLedger(month: month, dailyWage: wage, days: days)
    }

    /// 月汇总 (PRD 4.6.1)：结算总额、应出勤日数、扣款合计、请假天数、白干时长合计。
    /// 结算总额 = 当月各应出勤日结算之和；本月直接取本月累计 (今天之前的结算 + 今日已赚，未来日子不计入)。
    /// 扣款、请假、白干按整月的日记录合计。
    func summary(_ ledger: MonthLedger) -> HistoryMonthSummary {
        let month = ledger.month
        let isCurrent = month == source.today.date.yearMonth
        let settled = isCurrent
            ? source.today.monthToDate
            : ledger.days.compactMap(\.settlement).map(\.cap).reduce(0, +)
        let deducted = ledger.days.compactMap(\.settlement).map(\.deductionTotal).reduce(0, +)
        let leaveDays = ledger.days.map(\.leaveDays).reduce(0, +)
        let unpaid = ledger.days.map(\.unpaidWorkMilliseconds).reduce(0, +)
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

extension UnpaidWorkSegment {
    /// 这段白干的时长 (毫秒)，`day` 是它所在的日子。计时中的那段算到此刻，最晚到当天 23:59:59，
    /// 与 `advance` 自动停止的结果一致 (PRD 4.3.5 #12)；结束早于开始的段按 0 计。
    func milliseconds(on day: LocalDate, now: Moment) -> Int {
        let end = end ?? min(now.date, now.unpaidWorkCutoff(on: day))
        return max(0, Int((end.timeIntervalSince(start) * 1000).rounded(.down)))
    }
}

extension Format {
    /// 扣款合计：有扣款时如「−¥550」，没有时为「¥0」，不出现「−¥0」。
    static func deductionOrZero(_ amount: Decimal) -> String {
        amount > 0 ? deduction(amount) : money(0)
    }
}
