import Foundation

/// 目标管理页 (PRD F8，页面 P3) 列表里的一行，文字已格式化好。
public struct GoalRow: Sendable, Equatable, Identifiable {
    public let id: Int
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
        let current = active.map { GoalRow(id: $0.id, name: $0.name, statusLabel: "累计中", detail: $0.amountText) }
        let completed = state.goals.compactMap { goal -> (Goal, Date)? in
            if case .completed(let at) = goal.status { (goal, at) } else { nil }
        }
        let done = completed.sorted { $0.1 > $1.1 }.map { goal, at in
            let day = Moment(date: at, timeZone: now.timeZone).localDate
            let detail = "\(Format.money(goal.amount)) · \(Format.monthDay(day, relativeTo: today.date))达成"
            return GoalRow(id: goal.id, name: goal.name, statusLabel: "已完成", detail: detail)
        }
        return [current].compactMap { $0 } + done
    }
}
