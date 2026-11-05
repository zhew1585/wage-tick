import Foundation

/// 目标管理页 (PRD F8，页面 P3) 列表里的一行，文字已格式化好。
public struct GoalRow: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    /// 如「累计中」「排队中」「已完成」。
    public let statusLabel: String
    /// 累计中为「¥3000 / ¥10000」；排队中为目标金额「¥3000」；已完成为「¥500 · 2月11日达成」，不在今年时带年份。
    public let detail: String
    /// 所在分组 (PRD F8：累计中、排队中、已完成三组)。
    public let kind: Kind
    /// 目标金额，截掉末尾 0，如「3000.5」，编辑时直接填进输入框。
    public let amountInput: String

    public enum Kind: Sendable, Equatable {
        case accumulating, queued, completed
    }

    /// 能否改名称和金额：排队中和累计中可以，已完成冻结 (PRD 4.5.2)。
    public var canEdit: Bool { kind != .completed }
    /// 能否拖动排序：只有排队中，累计中固定在最前【D6】。
    public var canReorder: Bool { kind == .queued }
}

extension GoalRow {
    /// 列表顺序：累计中在最前，排队中按队列顺序，已完成按完成时间倒序。
    /// `active`：累计中目标的卡片，与面板目标区同一份。
    static func rows(state: AppState, active: ActiveGoalCard?, today: Today, now: Moment) -> [GoalRow] {
        let current = state.accumulatingGoal.flatMap { current in
            active.map { GoalRow(goal: current.goal, statusLabel: "累计中", detail: $0.amountText, kind: .accumulating) }
        }
        let queued = state.goals.filter(\.status.isQueued).map { goal in
            GoalRow(goal: goal, statusLabel: "排队中", detail: Format.money(goal.amount), kind: .queued)
        }
        let completed = state.goals.compactMap { goal -> (Goal, Date)? in
            if case .completed(let at) = goal.status { (goal, at) } else { nil }
        }
        let done = completed.sorted { $0.1 > $1.1 }.map { goal, at in
            let day = Moment(date: at, timeZone: now.timeZone).localDate
            let detail = "\(Format.money(goal.amount)) · \(Format.monthDay(day, relativeTo: today.date))达成"
            return GoalRow(goal: goal, statusLabel: "已完成", detail: detail, kind: .completed)
        }
        return [current].compactMap { $0 } + queued + done
    }

    private init(goal: Goal, statusLabel: String, detail: String, kind: Kind) {
        self.init(
            id: goal.id, name: goal.name, statusLabel: statusLabel, detail: detail,
            kind: kind, amountInput: Format.trimmed(goal.amount)
        )
    }
}
