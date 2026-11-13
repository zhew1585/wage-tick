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
    /// 这天开始的白干段，连同各段时长，按开始时刻先后。跨过零点的段整段算在开始这天。
    let unpaidWork: [TimedSegment]
    /// 这天生效的作息 (未经请假调整)：请假的时段、天数据此推导。
    let schedule: WorkSchedule

    var unpaidWorkMilliseconds: Int { unpaidWork.map(\.milliseconds).reduce(0, +) }

    /// 请假天数 (PRD 4.6.1)：请掉的有效工时 ÷ 标准工时，四舍五入到 2 位，全天计 1；不应出勤的日子不算。
    var leaveDays: Decimal {
        guard isAttendanceDay, let leave = record?.leave else { return 0 }
        guard !leave.isFullDay(schedule) else { return 1 }
        return Format.round(Decimal(schedule.leaveWorkMinutes(leave.range)) / Decimal(schedule.standardMinutes), scale: 2)
    }
}

/// 一段白干与它推导出的时长 (毫秒)，计时中的那段算到此刻 (最晚到自动停止时刻)。
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
                    TimedSegment(segment: $0, milliseconds: clock.milliseconds($0, on: date))
                },
                schedule: inputs.profile.schedule(on: date)
            )
        }
        return MonthLedger(month: month, dailyWage: wage, days: days)
    }

    /// 月汇总 (PRD 4.6.1)：结算总额、应出勤日数、扣款合计、请假天数、白干时长合计，以及挣到满额工资的比例。
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
        let unpaidText = Format.compactDuration(milliseconds: unpaid)
        let full = ledger.dailyWage * Decimal(ledger.attendanceDayCount)
        let progress = full > 0 ? min(max(NSDecimalNumber(decimal: settled / full).doubleValue, 0), 1) : 0
        let figuresLine = [
            "应出勤 \(ledger.attendanceDayCount)", "扣 \(Format.money(deducted))",
            "请假 \(Format.trimmed(leaveDays))", "白干 \(unpaidText)",
        ].joined(separator: " · ")
        return HistoryMonthSummary(
            month: month,
            title: "\(month.year)年\(month.month)月",
            shortTitle: month.year == today.year ? "\(month.month)月" : "\(month.year)年\(month.month)月",
            isCurrentMonth: isCurrent,
            isInstallMonth: month == inputs.profile.installDate.yearMonth,
            total: Format.money(settled),
            attendance: HistoryFigure(title: "应出勤", value: "\(ledger.attendanceDayCount) 天"),
            deduction: HistoryFigure(title: "扣款", value: Format.money(deducted), isLoss: deducted > 0),
            leave: HistoryFigure(title: "请假", value: "\(Format.trimmed(leaveDays)) 天"),
            unpaidWork: HistoryFigure(title: "白干", value: unpaidText),
            progress: progress,
            figuresLine: figuresLine,
            settled: settled,
            deducted: deducted
        )
    }
}

extension Format {
    /// 扣款：有扣款时如「−¥550」，没有时为「¥0」，不出现「−¥0」。
    static func deductionOrZero(_ amount: Decimal) -> String {
        amount > 0 ? deduction(amount) : money(0)
    }

    /// 历史里的时长 (设计稿 760)：不满 1 小时只写分钟，如「45m」「0m」；满 1 小时分钟补足两位，如「2h05m」。
    static func compactDuration(milliseconds: Int) -> String {
        let minutes = max(0, milliseconds) / 60_000
        guard minutes >= 60 else { return "\(minutes)m" }
        return "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m"
    }

    /// 日历格子里的金额：四舍五入到元，如「¥952」(格子窄，放不下小数)。
    static func wholeMoney(_ amount: Decimal) -> String {
        money(round(amount, scale: 0))
    }
}
