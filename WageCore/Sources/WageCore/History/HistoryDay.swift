import Foundation

/// 月日历 (F11)：某个月的汇总与每一天。
public struct HistoryMonth: Sendable, Equatable {
    /// 与月列表里同一个月的汇总相同。
    public let summary: HistoryMonthSummary
    /// 日历按周一至周日排，1 号前面空几格：1 号是周一时为 0，周日时为 6。
    public let leadingBlanks: Int
    /// 当月每一天，按日期升序。
    public let days: [HistoryDay]
    /// 该月月薪的数值，改月薪表单据此预填；任意月份可在月薪条改 (PRD 4.2.1 #2、4.6.1)。
    public let monthlySalary: Decimal
    /// 月薪条的小标题，如「本月月薪 · 应出勤 20 天」；往月写「2月月薪 · 应出勤 20 天」。
    public let salaryCaption: String
    /// 月薪条的数值，如「¥20000 → 日薪 ¥1000」。
    public let salaryText: String

    /// 日历底部的月小结：已结算 (同结算总额) 与扣款、请假、白干。
    public var footer: [HistoryFigure] {
        [HistoryFigure(title: "已结算", value: summary.total), summary.deduction, summary.leave, summary.unpaidWork]
    }

    /// 日历表头，与 `leadingBlanks` 同样从周一排起。
    public static let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]
}

/// 月日历里的一天。
public struct HistoryDay: Sendable, Equatable, Identifiable {
    public let date: LocalDate
    /// 格子里的日号，如「11」。
    public let dayText: String
    /// 颜色类型 (PRD 4.6.1)。
    public let kind: CalendarDayKind
    /// 是否今天：另外标出 (如描边)，不遮住当天的颜色类型。
    public let isToday: Bool
    /// 格子里的金额，四舍五入到元，如「¥950」：已过的应出勤日为结算，今天为今日已赚；未来与不应出勤的日子为 nil。
    public let amountText: String?
    /// 格子里的小字：请假写时段 (如「下午」)，改成不上班写「改休」，改成上班写「改班」；其余为 nil。
    public let tag: String?
    /// 点开这一天看到的单日详情。
    public let detail: HistoryDayDetail

    public var id: LocalDate { date }
}

/// 日历的颜色类型 (PRD 4.6.1，设计稿 P5 月日历 · 760)。「今天」不是一种类型，见 `HistoryDay.isToday`。
public enum CalendarDayKind: Sendable, Equatable, CaseIterable {
    /// 满勤：已过 (含今天) 的应出勤日，没有扣钱也没请假。
    case fullAttendance
    /// 被扣钱：有扣钱记录。
    case deducted
    /// 请假：全天或半天。
    case leave
    /// 休息日：不应出勤。
    case rest
    /// 改成不上班：牛马用单日覆盖改成不上班的日子 (#15)。改成上班的日子按上班日的类型标，格子另写「改班」。
    case override
    /// 未到：未来的应出勤日，还没结算，不标满勤。PRD 未列，待定。
    case upcoming

    /// 图例文案。
    public var label: String {
        switch self {
        case .fullAttendance: "满勤"
        case .deducted: "被扣钱"
        case .leave: "请假"
        case .rest: "休息日"
        case .override: "改成不上班"
        case .upcoming: "未到"
        }
    }

    /// 图例里列出的类型，按此顺序 (设计稿)：休息日 (无底无框) 与未到 (白格) 一看就懂，不列。
    public static let legend: [CalendarDayKind] = [.fullAttendance, .deducted, .leave, .override]

    /// 「今天」的图例文案。
    public static let todayLabel = "今天"
}

/// 单日详情 (PRD 4.6.1)：结算、扣款明细、请假、白干段、判定来源。文字已格式化好，外壳原样展示。
public struct HistoryDayDetail: Sendable, Equatable {
    /// 如「2月11日 周三」；不在今年时带年份。
    public let title: String
    public let source: AttendanceSource
    /// 已过的应出勤日为「当天结算」，今天为「今日已赚」「今日上限」，未来为「预计结算」；不应出勤的日子没有。
    /// 详情页把第一项放大展示。
    public let stats: [StatItem]
    /// 结算的算式，如「日薪 1000 − 请假 500 − 扣款 50」；没扣钱也没请假扣薪、或不应出勤时为 nil。
    public let breakdown: String?
    /// 扣款明细，按记录先后。不应出勤的日子 (单日覆盖或节假日表更新后变成不上班) 已有的也列出，不计入结算，可删除。
    public let deductions: [DeductionItem]
    /// 请假，如「下午假 · 扣薪 50% · −¥500」；没请假为 nil。不应出勤的日子已有的同样列出。
    public let leave: HistoryLine?
    /// 白干段，按开始时刻先后，标题如「18:00 – 19:30」、数值如「1h30m」；疑似通宵、计时中写在 `detail`。
    /// 每段倒贴见 `editing.unpaidWorkItems`。
    public let unpaidWork: [HistoryLine]
    /// 不应出勤的日子还留着扣钱或请假时的提示，否则为 nil (#14 遗留)。
    public let notice: String?
    /// 编辑入口 (PRD 4.6.1 可编辑内容)。
    public let editing: DayEditing

    /// 判定来源一项，如「判定来源 法定节假日」。
    public var sourceItem: StatItem { StatItem(title: "判定来源", value: source.label) }
}

/// 详情里的一行：标题、可选说明、右侧数值。
public struct HistoryLine: Sendable, Equatable {
    public let title: String
    public let detail: String?
    public let value: String

    public init(title: String, detail: String?, value: String) {
        self.title = title
        self.detail = detail
        self.value = value
    }
}

extension Snapshot {
    /// 某个月的日历 (F11)；不在安装当月至本月之间时为 nil。只在调用时推导。
    public func historyMonth(_ month: YearMonth) -> HistoryMonth? {
        guard let history else { return nil }
        let ledger = HistoryLedger(history)
        guard ledger.months.contains(month) else { return nil }
        return ledger.month(month)
    }
}

extension HistoryLedger {
    func month(_ month: YearMonth) -> HistoryMonth {
        let monthLedger = monthLedger(for: month)
        let salary = inputs.profile.salary(for: month)
        let salaryTitle = month == today.yearMonth ? "本月月薪" : "\(month.month)月月薪"
        return HistoryMonth(
            summary: summary(monthLedger),
            // weekday 1 为周日、2 为周一：换成从周一起数的 0 至 6。
            leadingBlanks: (monthLedger.days[0].date.weekday + 5) % 7,
            days: monthLedger.days.map { day($0, dailyWage: monthLedger.dailyWage) },
            monthlySalary: salary,
            salaryCaption: "\(salaryTitle) · 应出勤 \(monthLedger.attendanceDayCount) 天",
            salaryText: "\(Format.money(salary)) → 日薪 \(Format.money(monthLedger.dailyWage))"
        )
    }

    func day(_ day: DayLedger, dailyWage: Decimal) -> HistoryDay {
        // 不应出勤的日子没有结算，已有的扣钱、请假按当月日薪折算出来展示，不计入任何收入。
        let shown = day.settlement ?? day.record.map { DaySettlement(dailyWage: dailyWage, record: $0) }
        let unpaidWork = unpaidWorkLines(day)
        return HistoryDay(
            date: day.date,
            dayText: "\(day.date.day)",
            kind: kind(day),
            isToday: day.date == today,
            amountText: amountText(day),
            tag: tag(day),
            detail: HistoryDayDetail(
                title: Format.date(day.date, relativeTo: today),
                source: day.source,
                stats: stats(day),
                breakdown: day.settlement.flatMap(breakdown),
                deductions: shown?.deductions.map(DeductionItem.init) ?? [],
                leave: leaveLine(day, settlement: shown),
                unpaidWork: unpaidWork,
                notice: staleNotice(day),
                editing: editing(day, unpaidWorkLines: unpaidWork, dailyWage: dailyWage)
            )
        )
    }

    /// 颜色类型，先命中者为准：改成不上班 > 休息日 > 请假 > 被扣钱 > 未到 > 满勤。改成上班的日子按上班日往下判。
    private func kind(_ day: DayLedger) -> CalendarDayKind {
        if day.source == .override, !day.isAttendanceDay { return .override }
        guard day.isAttendanceDay, let settlement = day.settlement else { return .rest }
        if day.record?.leave != nil { return .leave }
        if !settlement.deductions.isEmpty { return .deducted }
        return day.date > today ? .upcoming : .fullAttendance
    }

    /// 格子金额：已过的应出勤日为结算，今天为今日已赚 (今天没有收入推导时不写)。
    private func amountText(_ day: DayLedger) -> String? {
        guard day.date <= today, let settlement = day.settlement else { return nil }
        let amount = day.date == today ? inputs.today.earnings?.earned : settlement.cap
        return amount.map(Format.wholeMoney)
    }

    /// 格子小字：请假时段优先，其次单日覆盖的方向。
    private func tag(_ day: DayLedger) -> String? {
        if day.isAttendanceDay, let leave = day.record?.leave { return leave.period.label }
        return switch day.record?.override {
        case .dayOff: "改休"
        case .attendanceDay: "改班"
        case nil: nil
        }
    }

    /// 结算的算式：日薪减去请假扣薪与扣钱合计，数字不带 ¥；两样都没有时不写。
    private func breakdown(_ settlement: DaySettlement) -> String? {
        let fines = settlement.deductions.map(\.money).reduce(0, +)
        guard settlement.leaveDeduction > 0 || fines > 0 else { return nil }
        let leave = settlement.leaveDeduction > 0 ? ["请假 \(Format.trimmed(settlement.leaveDeduction))"] : []
        let fine = fines > 0 ? ["扣款 \(Format.trimmed(fines))"] : []
        return (["日薪 \(Format.trimmed(settlement.dailyWage))"] + leave + fine).joined(separator: " − ")
    }

    private func stats(_ day: DayLedger) -> [StatItem] {
        guard let settlement = day.settlement else { return [] }
        if day.date == today, let earnings = inputs.today.earnings {
            return [
                StatItem(title: "今日已赚", value: Format.money(earnings.earned)),
                StatItem(title: incomeTitle(day.date), value: Format.money(earnings.cap)),
            ]
        }
        let title = day.date < today ? "当天结算" : incomeTitle(day.date)
        return [StatItem(title: title, value: Format.money(settlement.cap))]
    }

    /// 某天收入项的标题：过去为「结算」，今天为「今日上限」，未来为「预计结算」。详情、请假与扣钱表单共用。
    func incomeTitle(_ date: LocalDate) -> String {
        date < today ? "结算" : (date == today ? "今日上限" : "预计结算")
    }

    private func leaveLine(_ day: DayLedger, settlement: DaySettlement?) -> HistoryLine? {
        guard let settlement, let leave = day.record?.leave else { return nil }
        return HistoryLine(
            title: "\(leave.period.label)假",
            detail: "扣薪 \(Format.percent(leave.deductionPercent / 100))",
            value: Format.deductionOrZero(settlement.leaveDeduction)
        )
    }

    /// 白干段：结束了的写「开始 – 结束」，到 23:59:59 被自动停止 (或该停还没推进) 的标疑似通宵 (PRD 4.3.5 #12)，
    /// 计时中的写「开始 起」。时长如「1h30m」。
    private func unpaidWorkLines(_ day: DayLedger) -> [HistoryLine] {
        let now = inputs.now
        let cutoff = now.unpaidWorkCutoff(on: day.date)
        let clock = { (date: Date) in Format.time(Moment(date: date, timeZone: now.timeZone)) }
        return day.unpaidWork.map { timed in
            let segment = timed.segment
            let duration = Format.compactDuration(milliseconds: timed.milliseconds)
            if segment.isRunning(on: day.date, now: now) {
                return HistoryLine(title: "\(clock(segment.start)) 起", detail: "计时中", value: duration)
            }
            return HistoryLine(
                title: "\(clock(segment.start)) – \(clock(segment.end ?? cutoff))",
                detail: segment.isSuspectedAllNighter(on: day.date, now: now) ? "疑似通宵" : nil,
                value: duration
            )
        }
    }

    /// 不应出勤的日子还留着扣钱或请假：提示不计入、可删掉。
    private func staleNotice(_ day: DayLedger) -> String? {
        guard !day.isAttendanceDay, let record = day.record, !record.deductions.isEmpty || record.leave != nil else { return nil }
        return "这天不上班，下面的扣钱和请假不计入结算，可以删掉"
    }
}
