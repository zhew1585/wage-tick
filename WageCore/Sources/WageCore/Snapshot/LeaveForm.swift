import Foundation

/// 请假表单 (PRD F6) 应展示的内容，文字已格式化好，外壳原样展示。
/// 今天的来自快照的 `leaveForm`，其他日子的来自单日详情的 `DayEditing.leave` (历史编辑，#15)。
/// 表单里的实时汇总：外壳把待保存的命令先对状态副本 `apply` 一次，再取这份快照的 `leaveForm`，不自行计算。
public struct LeaveForm: Sendable, Equatable {
    /// 这天已有的请假，供编辑时预填；nil 表示还没请。
    public let current: Leave?
    /// 已有请假的一句话描述，如「已请下午假 · 扣薪 50%」；没请假时为 nil。
    public let currentText: String?
    /// 汇总：当日计划 (今天为「今天改为 10:00–12:00 上班」)、请假扣薪 (有时如「−¥500」)、
    /// 收入项 (今天为今日上限，历史里的过去日子为结算，未来为预计结算)。
    public let summary: [StatItem]
    /// 请假扣薪，不带负号，如「¥500」：比例输入框右侧的「= ¥500」。
    public let deductionText: String
    /// 各时段请掉的工时，如全天「10:00–18:00」、上午「10:00–12:00」，显示在时段选项下方。
    public let periodHours: [LeavePeriod: String]
    /// 能否再新请一条：已请全天假时只能修改或撤销 (PRD 4.4.2 #4)。
    public let canRequest: Bool
}

extension LeavePeriod {
    /// 表单里的时段名，如「下午」。
    public var label: String {
        switch self {
        case .fullDay: "全天"
        case .morning: "上午"
        case .afternoon: "下午"
        }
    }
}

extension LeaveForm {
    /// 今天不应出勤时没有表单。
    init?(today: Today, now: Moment) {
        guard let settlement = today.settlement else { return nil }
        self.init(
            leave: today.leave, settlement: settlement, schedule: today.schedule, on: today.date,
            planTitle: Self.planTitle(today.date, today: today.date), capTitle: "今日上限", now: now
        )
    }

    /// 汇总里当日计划的标题：今天为「今天改为」(设计稿 F6)，历史里的其他日子为「当日计划」。
    static func planTitle(_ day: LocalDate, today: LocalDate) -> String {
        day == today ? "今天改为" : "当日计划"
    }

    /// 某个应出勤日的表单。`schedule` 是这天生效的作息 (未经半天假调整)；
    /// `planTitle`、`capTitle` 是汇总里当日计划与收入项的标题。
    init(
        leave: Leave?, settlement: DaySettlement, schedule: WorkSchedule, on day: LocalDate,
        planTitle: String, capTitle: String, now: Moment
    ) {
        let plan = DayPlan(schedule: schedule, leave: leave?.period, on: day, now: now)
        let clock = { (date: Date) in Format.time(Moment(date: date, timeZone: now.timeZone)) }
        let span = { (start: Date, end: Date) in "\(clock(start))–\(clock(end))" }
        current = leave
        canRequest = leave?.period != .fullDay
        currentText = leave.map { "已请\($0.period.label)假 · 扣薪 \(Format.percent($0.deductionPercent / 100))" }
        // 关闭午休时的中点可能带秒，只显示到分。
        let planText = plan.map { "\(span($0.start, $0.end)) 上班" } ?? "全天请假"
        summary = [
            StatItem(title: planTitle, value: planText),
            StatItem(title: "请假扣薪", value: Format.deductionOrZero(settlement.leaveDeduction)),
            StatItem(title: capTitle, value: Format.money(settlement.cap)),
        ]
        deductionText = Format.money(settlement.leaveDeduction)
        periodHours = Dictionary(uniqueKeysWithValues: LeavePeriod.allCases.map { period in
            let hours = DayPlan.leaveSpan(period, schedule: schedule, on: day, now: now)
            return (period, span(hours.start, hours.end))
        })
    }
}
