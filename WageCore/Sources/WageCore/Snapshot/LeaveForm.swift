import Foundation

/// 请假表单 (PRD F6) 应展示的内容，文字已格式化好，外壳原样展示。
/// 今天的来自快照的 `leaveForm`，其他日子的来自单日详情的 `DayEditing.leave` (历史编辑，#15)。
/// 表单里的实时汇总：外壳把待保存的命令先对状态副本 `apply` 一次，再取这份快照的 `leaveForm`，不自行计算。
/// 拖时间条时的时段文字、默认比例不用试算，直接问 `bar`。
public struct LeaveForm: Sendable, Equatable {
    /// 这天已有的请假，供编辑时预填；nil 表示还没请。
    public let current: Leave?
    /// 已有请假的一句话描述，如「已请假 14:00–16:00 · 扣薪 28.57%」「已请全天假 · 扣薪 100.00%」；没请假时为 nil。
    public let currentText: String?
    /// 汇总：当日计划 (今天为「今天上班 10:00–14:00、16:00–18:00」，全天请假为「全天请假」)、
    /// 请假扣薪 (有时如「−¥500」)、收入项 (今天为今日上限，历史里的过去日子为结算，未来为预计结算)。
    public let summary: [StatItem]
    /// 比例输入框右侧的请假扣薪，如「= ¥500」。
    public let deductionText: String
    /// 「请哪段」时间条：这天的计划上下班、饭点、刻度与快捷时段。
    public let bar: LeaveBar
    /// 能否新请一条：一天只有一条，已请假时只能修改或撤销 (PRD 4.4.2 #4)。
    public let canRequest: Bool
}

extension LeaveForm {
    /// 今天不应出勤时没有表单。
    init?(today: Today) {
        guard let settlement = today.settlement else { return nil }
        self.init(
            leave: today.leave, settlement: settlement, schedule: today.schedule,
            planTitle: Self.planTitle(today.date, today: today.date), capTitle: "今日上限"
        )
    }

    /// 汇总里当日计划的标题：今天为「今天上班」(设计稿 F6)，历史里的其他日子为「当日计划」。
    static func planTitle(_ day: LocalDate, today: LocalDate) -> String {
        day == today ? "今天上班" : "当日计划"
    }

    /// 某个应出勤日的表单。`schedule` 是这天生效的作息 (未经请假调整)；
    /// `planTitle`、`capTitle` 是汇总里当日计划与收入项的标题。
    init(leave: Leave?, settlement: DaySettlement, schedule: WorkSchedule, planTitle: String, capTitle: String) {
        current = leave
        canRequest = leave == nil
        currentText = leave.map { leave in
            let percent = "扣薪 \(Format.percent(leave.deductionPercent / 100))"
            return leave.isFullDay(schedule) ? "已请全天假 · \(percent)" : "已请假 \(Format.span(leave.range.span)) · \(percent)"
        }
        summary = [
            StatItem(title: planTitle, value: Self.planText(leave: leave, schedule: schedule)),
            StatItem(title: "请假扣薪", value: Format.deductionOrZero(settlement.leaveDeduction)),
            StatItem(title: capTitle, value: Format.money(settlement.cap)),
        ]
        deductionText = "= \(Format.money(settlement.leaveDeduction))"
        bar = LeaveBar(schedule: schedule)
    }

    /// 当日计划的各段上班，只按请假切开，如「10:00–14:00、16:00–18:00」；全天请假为「全天请假」。
    private static func planText(leave: Leave?, schedule: WorkSchedule) -> String {
        guard let leave else { return Format.span(schedule.span) }
        guard let plan = schedule.leavePlan(leave.range) else { return "全天请假" }
        return plan.stretches.map(Format.span).joined(separator: "、")
    }
}

extension Leave {
    /// 请掉了这天的全部工时 (全天请假)：按休息日呈现，没有当日计划 (PRD 4.3.2 #3)。
    func isFullDay(_ schedule: WorkSchedule) -> Bool {
        schedule.leavePlan(range) == nil
    }
}

extension Format {
    /// 一天中的时刻，如「09:05」。
    static func time(_ time: TimeOfDay) -> String {
        String(format: "%02d:%02d", time.hour, time.minute)
    }

    /// 一天里的一段时刻，如「10:00–14:00」。
    static func span(_ span: MinuteSpan) -> String {
        "\(time(TimeOfDay(minutesSinceMidnight: span.start)))–\(time(TimeOfDay(minutesSinceMidnight: span.end)))"
    }

    /// 请假时长，如「2 小时」「40 分钟」「1 小时 30 分」。
    static func leaveDuration(minutes: Int) -> String {
        switch (minutes / 60, minutes % 60) {
        case (0, let rest): "\(rest) 分钟"
        case (let hours, 0): "\(hours) 小时"
        case (let hours, let rest): "\(hours) 小时 \(rest) 分"
        }
    }
}
