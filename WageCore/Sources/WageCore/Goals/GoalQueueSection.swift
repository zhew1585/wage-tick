import Foundation

/// 面板目标区里累计中目标下方的排队部分 (PRD F9)，文字已格式化好，外壳原样展示。
/// 只在有排队中目标时出现；只有 1 个目标时没有 (AC-GPRG-08)。
public struct GoalQueueSection: Sendable, Equatable {
    /// 展开时按队列顺序紧跟累计中目标的排队中目标，与累计中合计最多 3 个 (AC-GPRG-07)；收起时为空。
    public let queued: [QueuedGoalCard]
    /// 底部按钮：收起时「显示更多 (N)」，N 为全部排队中目标数；展开时「收起」。点击发 `.toggleGoalQueueExpanded`。
    public let toggleTitle: String
}

/// 排队中目标的卡片。
public struct QueuedGoalCard: Sendable, Equatable, Identifiable {
    /// 目标编号，与目标管理列表里的同一行一致。
    public let id: Int
    public let name: String
    /// 目标金额，如「¥3000」。
    public let amountText: String
    /// 如「排队中 · 预计 2月27日」，不在今年时「排队中 · 预计 2027年1月」(PRD 4.5.3 #5)。
    public let estimate: String
}

extension GoalQueueSection {
    /// 展开时面板目标区最多显示几个目标 (累计中 + 排队中)。
    static let expandedLimit = 3

    /// `active`：累计中目标的卡片，排队中目标的预计完成日从它的预计完成日之后起数。
    init?(state: AppState, active: ActiveGoalCard?, today: Today, holidays: HolidayTable) {
        let queued = state.goals.filter(\.status.isQueued)
        guard let active, !queued.isEmpty else { return nil }
        guard state.settings.goalQueueExpanded else {
            self.init(queued: [], toggleTitle: "显示更多 (\(queued.count))")
            return
        }
        let rule = AttendanceRule(holidays: holidays)
        var previousFinish = active.finishDate
        let cards = queued.prefix(Self.expandedLimit - 1).map { goal in
            let finish = rule.attendanceDay(
                ActiveGoalCard.workDays(for: goal.amount, dailyWage: today.dailyWage),
                after: previousFinish
            )
            previousFinish = finish
            return QueuedGoalCard(goal: goal, finish: finish, today: today.date)
        }
        self.init(queued: cards, toggleTitle: "收起")
    }
}

extension QueuedGoalCard {
    /// 排队中目标的预计完成日 (PRD 4.5.3 #5)：从前一个目标的预计完成日之后起，
    /// 按当月日薪数 ceil(目标金额 ÷ 日薪) 个应出勤日，跨月、跨年都仍按当月日薪【D7】。
    init(goal: Goal, finish: LocalDate, today: LocalDate) {
        id = goal.id
        name = goal.name
        amountText = Format.money(goal.amount)
        let date = finish.year == today.year ? Format.monthDay(finish) : Format.yearMonth(finish)
        estimate = "排队中 · 预计 \(date)"
    }
}

extension Format {
    /// 年月，如「2027年1月」。
    static func yearMonth(_ day: LocalDate) -> String {
        "\(day.year)年\(day.month)月"
    }
}
