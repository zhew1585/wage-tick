import Foundation

/// 月日历 (F11)：某个月的汇总与每一天。
public struct HistoryMonth: Sendable, Equatable {
    /// 与月列表里同一个月的汇总相同。
    public let summary: HistoryMonthSummary
    /// 日历按周一至周日排，1 号前面空几格：1 号是周一时为 0，周日时为 6。
    public let leadingBlanks: Int
    /// 当月每一天，按日期升序。
    public let days: [HistoryDay]

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
    /// 点开这一天看到的单日详情。
    public let detail: HistoryDayDetail

    public var id: LocalDate { date }
}

/// 日历的颜色类型 (PRD 4.6.1)。「今天」不是一种类型，见 `HistoryDay.isToday`。
public enum CalendarDayKind: Sendable, Equatable, CaseIterable {
    /// 满勤：已过 (含今天) 的应出勤日，没有扣钱也没请假。
    case fullAttendance
    /// 被扣钱：有扣钱记录。
    case deducted
    /// 请假：全天或半天。
    case leave
    /// 休息日：不应出勤。
    case rest
    /// 单日覆盖：预留给 #15，本票不会出现。
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
        case .override: "单日覆盖"
        case .upcoming: "未到"
        }
    }

    /// 图例里列出的类型，按此顺序。单日覆盖只在类型上预留 (#15)，先不出现。
    public static let legend: [CalendarDayKind] = [.fullAttendance, .deducted, .leave, .rest, .upcoming]

    /// 「今天」的图例文案。
    public static let todayLabel = "今天"
}

/// 单日详情 (PRD 4.6.1)：结算、扣款明细、请假、白干段、判定来源。文字已格式化好，外壳原样展示。
public struct HistoryDayDetail: Sendable, Equatable {
    /// 如「2月11日 周三」；不在今年时带年份。
    public let title: String
    public let source: AttendanceSource
    /// 已过的应出勤日为「结算」，今天为「今日已赚」「今日上限」，未来为「预计结算」；不应出勤的日子没有。
    public let stats: [StatItem]
    /// 扣款明细，按记录先后。
    public let deductions: [DeductionItem]
    /// 请假，如「下午假 · 扣薪 50% · −¥500」；没请假为 nil。
    public let leave: HistoryLine?
    /// 白干段，按开始时刻先后，如「18:00 至 19:30 · 1:30」；疑似通宵、计时中写在 `detail`。
    public let unpaidWork: [HistoryLine]
    /// 如「白干 1:30 · 倒贴 ¥214.2857」；没有白干段为 nil。
    public let unpaidWorkSummary: String?

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
        return HistoryMonth(
            summary: summary(monthLedger),
            // weekday 1 为周日、2 为周一：换成从周一起数的 0 至 6。
            leadingBlanks: (monthLedger.days[0].date.weekday + 5) % 7,
            days: monthLedger.days.map { day($0, dailyWage: monthLedger.dailyWage) }
        )
    }

    func day(_ day: DayLedger, dailyWage: Decimal) -> HistoryDay {
        HistoryDay(
            date: day.date,
            dayText: "\(day.date.day)",
            kind: kind(day),
            isToday: day.date == today,
            detail: HistoryDayDetail(
                title: Format.date(day.date, relativeTo: today),
                source: day.source,
                stats: stats(day),
                deductions: day.settlement?.deductions.map(DeductionItem.init) ?? [],
                leave: leaveLine(day),
                unpaidWork: unpaidWorkLines(day),
                unpaidWorkSummary: unpaidWorkSummary(day, dailyWage: dailyWage)
            )
        )
    }

    /// 颜色类型，先命中者为准：休息日 > 请假 > 被扣钱 > 未到 > 满勤。单日覆盖 (#15) 将排在最前。
    private func kind(_ day: DayLedger) -> CalendarDayKind {
        guard day.isAttendanceDay, let settlement = day.settlement else { return .rest }
        if day.record?.leave != nil { return .leave }
        if !settlement.deductions.isEmpty { return .deducted }
        return day.date > today ? .upcoming : .fullAttendance
    }

    private func stats(_ day: DayLedger) -> [StatItem] {
        guard let settlement = day.settlement else { return [] }
        if day.date > today {
            return [StatItem(title: "预计结算", value: Format.money(settlement.cap))]
        }
        if day.date == today, let earnings = inputs.today.earnings {
            return [
                StatItem(title: "今日已赚", value: Format.money(earnings.earned)),
                StatItem(title: "今日上限", value: Format.money(earnings.cap)),
            ]
        }
        return [StatItem(title: "结算", value: Format.money(settlement.cap))]
    }

    private func leaveLine(_ day: DayLedger) -> HistoryLine? {
        guard let settlement = day.settlement, let leave = day.record?.leave else { return nil }
        return HistoryLine(
            title: "\(leave.period.label)假",
            detail: "扣薪 \(Format.percent(leave.deductionPercent / 100))",
            value: Format.deductionOrZero(settlement.leaveDeduction)
        )
    }

    /// 白干段：结束了的写「开始 至 结束」，到 23:59:59 被自动停止 (或该停还没推进) 的标疑似通宵 (PRD 4.3.5 #12)，
    /// 计时中的写「开始 起」。
    private func unpaidWorkLines(_ day: DayLedger) -> [HistoryLine] {
        let now = inputs.now
        let cutoff = now.unpaidWorkCutoff(on: day.date)
        let clock = { (date: Date) in Format.time(Moment(date: date, timeZone: now.timeZone)) }
        return day.unpaidWork.map { timed in
            let segment = timed.segment
            let duration = Format.hoursMinutes(milliseconds: timed.milliseconds)
            if segment.isRunning(on: day.date, now: now) {
                return HistoryLine(title: "\(clock(segment.start)) 起", detail: "计时中", value: duration)
            }
            return HistoryLine(
                title: "\(clock(segment.start)) 至 \(clock(segment.end ?? cutoff))",
                detail: segment.isSuspectedAllNighter(on: day.date, now: now) ? "疑似通宵" : nil,
                value: duration
            )
        }
    }

    /// 倒贴 = 白干时长 × 时薪，时薪按该日生效作息的标准工时计算 (PRD 4.4.3 #4)。
    private func unpaidWorkSummary(_ day: DayLedger, dailyWage: Decimal) -> String? {
        guard !day.unpaidWork.isEmpty else { return nil }
        let milliseconds = day.unpaidWorkMilliseconds
        let owed = inputs.profile.schedule(on: day.date).owed(dailyWage: dailyWage, milliseconds: milliseconds)
        return "白干 \(Format.hoursMinutes(milliseconds: milliseconds)) · 倒贴 \(Format.money(owed))"
    }
}
