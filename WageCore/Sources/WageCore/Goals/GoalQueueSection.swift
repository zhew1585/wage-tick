import Foundation

/// 面板目标区里累计中目标下方的排队部分 (PRD F9)，文字已格式化好，外壳原样展示。
/// 只在有排队中目标时出现；只有 1 个目标时没有 (AC-GPRG-08)。
public struct GoalQueueSection: Sendable, Equatable {
    /// 展开时按队列顺序紧跟累计中目标的排队中目标，与累计中合计最多 3 个 (AC-GPRG-07)；收起时为空。
    public let queued: [QueuedGoalCard]
    /// 不论展开与否都直接列出的排队中目标，个数上限同 `queued` (760 设计稿的「攒钱队列」不再展开收起)。
    public let upcoming: [QueuedGoalCard]
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
    /// 面板攒钱队列里的短版预计，如「预计 2月27日」「预计 2027年1月」「暂时没法预计」。
    public let shortEstimate: String
}

extension GoalQueueSection {
    /// 展开时面板目标区最多显示几个目标 (累计中 + 排队中)。
    static let expandedLimit = 3

    /// `active`：累计中目标的卡片，排队中目标的预计完成日从它的预计完成日之后起数。
    init?(state: AppState, active: ActiveGoalCard?, today: Today, holidays: HolidayTable) {
        let queued = state.goals.filter(\.status.isQueued)
        guard let active, !queued.isEmpty else { return nil }
        let rule = AttendanceRule(holidays: holidays)
        var previousFinish = active.finishDate
        let cards = queued.prefix(Self.expandedLimit - 1).map { goal in
            // 日薪为 0 时 (PRD 4.3.5 #19) 前一个没法预计，后面的也都没法预计。
            let finish = previousFinish.flatMap { previous in
                ActiveGoalCard.workDays(for: goal.amount, dailyWage: today.dailyWage).map { rule.attendanceDay($0, after: previous) }
            }
            previousFinish = finish
            return QueuedGoalCard(goal: goal, finish: finish, today: today.date)
        }
        let expanded = state.settings.goalQueueExpanded
        self.init(
            queued: expanded ? cards : [],
            upcoming: cards,
            toggleTitle: expanded ? "收起" : "显示更多 (\(queued.count))"
        )
    }
}

extension QueuedGoalCard {
    /// 排队中目标的预计完成日 (PRD 4.5.3 #5)：从前一个目标的预计完成日之后起，
    /// 按当月日薪数 ceil(目标金额 ÷ 日薪) 个应出勤日，跨月、跨年都仍按当月日薪【D7】。
    /// `finish` 为 nil 时 (本月没有应出勤日，日薪为 0) 没法预计。
    init(goal: Goal, finish: LocalDate?, today: LocalDate) {
        id = goal.id
        name = goal.name
        amountText = Format.money(goal.amount)
        guard let finish else {
            shortEstimate = ActiveGoalCard.noEstimateShort
            estimate = "排队中 · \(shortEstimate)"
            return
        }
        let date = finish.year == today.year ? Format.monthDay(finish) : Format.yearMonth(finish)
        shortEstimate = "预计 \(date)"
        estimate = "排队中 · \(shortEstimate)"
    }
}

extension Format {
    /// 年月，如「2027年1月」。
    static func yearMonth(_ day: LocalDate) -> String {
        "\(day.year)年\(day.month)月"
    }
}
