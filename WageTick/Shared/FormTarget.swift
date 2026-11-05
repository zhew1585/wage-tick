import WageCore

/// 扣钱、请假表单作用的日子：今天 (今日概览面板) 或历史里的某一天 (单日详情，#15)。
/// 只决定发哪条命令、从试算后的快照哪里取预览，不做任何计算。
enum FormTarget: Equatable {
    case today
    case day(LocalDate)

    /// 扣钱表单的预览起点或终点：今天取面板的扣钱入口，历史取那一天的编辑入口。
    func deductionEntry(in snap: Snapshot) -> DeductionEntry? {
        switch self {
        case .today: snap.panel?.deductionEntry
        case .day(let date): snap.historyDay(date)?.detail.editing.deduction.content
        }
    }

    /// 请假表单的汇总：今天取快照的请假表单，历史取那一天的编辑入口。
    func leaveForm(in snap: Snapshot) -> LeaveForm? {
        switch self {
        case .today: snap.leaveForm
        case .day(let date): snap.historyDay(date)?.detail.editing.leave.content
        }
    }
}
