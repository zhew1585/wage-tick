import Foundation

/// 目标管理页 (PRD F8，页面 P3) 列表里的一行，文字已格式化好。
public struct GoalRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    /// 如「累计中」「已完成」。
    public let statusLabel: String
    /// 累计中为「¥3000 / ¥10000」；已完成为「¥500 · 2月11日达成」，不在今年时带年份。
    public let detail: String
}

extension GoalRow {
    /// 列表顺序：累计中在最前，已完成按完成时间倒序。
    /// `active`：累计中目标的卡片，与面板目标区同一份。
    static func rows(state: AppState, active: ActiveGoalCard?, today: Today, now: Moment) -> [GoalRow] {
        var rows: [GoalRow] = []
        if let current = state.accumulatingGoal, let card = active {
            rows.append(GoalRow(id: current.goal.id, name: current.goal.name, statusLabel: "累计中", detail: card.amountText))
        }
        let completed = state.goals.compactMap { goal -> (Goal, Date)? in
            if case .completed(let at) = goal.status { (goal, at) } else { nil }
        }
        for (goal, at) in completed.sorted(by: { $0.1 > $1.1 }) {
            let detail = "\(Format.money(goal.amount)) · \(Self.dayText(Moment(date: at, timeZone: now.timeZone).localDate, today: today.date))达成"
            rows.append(GoalRow(id: goal.id, name: goal.name, statusLabel: "已完成", detail: detail))
        }
        return rows
    }

    /// 如「2月11日」；不在今年时带年份，如「2026年12月30日」。
    private static func dayText(_ day: LocalDate, today: LocalDate) -> String {
        let year = day.year == today.year ? "" : "\(day.year)年"
        return "\(year)\(day.month)月\(day.day)日"
    }
}
