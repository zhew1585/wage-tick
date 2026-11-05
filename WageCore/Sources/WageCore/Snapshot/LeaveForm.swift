import Foundation

/// 请假表单 (PRD F6) 应展示的内容，文字已格式化好，外壳原样展示。
/// 今天的来自快照的 `leaveForm`，其他日子的来自单日详情的 `DayEditing.leave` (历史编辑，#15)。
/// 表单里的实时汇总：外壳把待保存的命令先对状态副本 `apply` 一次，再取这份快照的 `leaveForm`，不自行计算。
public struct LeaveForm: Sendable, Equatable {
    /// 这天已有的请假，供编辑时预填；nil 表示还没请。
    public let current: Leave?
    /// 已有请假的一句话描述，如「已请下午假 · 扣薪 50%」；没请假时为 nil。
    public let currentText: String?
    /// 汇总：当日计划、请假扣薪、今日上限 (历史里的过去日子为结算，未来为预计结算)。
    public let summary: [StatItem]
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
        self.init(leave: today.leave, settlement: settlement, plan: today.plan, capTitle: "今日上限", now: now)
    }

    /// 某个应出勤日的表单。`plan` 是当日计划，全天请假时为 nil；`capTitle` 是汇总里收入项的标题。
    init(leave: Leave?, settlement: DaySettlement, plan: DayPlan?, capTitle: String, now: Moment) {
        current = leave
        canRequest = leave?.period != .fullDay
        currentText = leave.map { "已请\($0.period.label)假 · 扣薪 \(Format.percent($0.deductionPercent / 100))" }
        let planText = plan.map { "\(Self.clock($0.start, now)) 至 \(Self.clock($0.end, now))" } ?? "全天请假"
        summary = [
            StatItem(title: "当日计划", value: planText),
            StatItem(title: "请假扣薪", value: Format.money(settlement.leaveDeduction)),
            StatItem(title: capTitle, value: Format.money(settlement.cap)),
        ]
    }

    /// 当日计划的时分，如「12:00」。关闭午休时的中点可能带秒，只显示到分。
    private static func clock(_ date: Date, _ now: Moment) -> String {
        Format.time(Moment(date: date, timeZone: now.timeZone))
    }
}
