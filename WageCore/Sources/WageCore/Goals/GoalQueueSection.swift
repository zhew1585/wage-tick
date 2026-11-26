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
    /// 如「排队中 · 预计 2月27日」，不在今年时「排队中 · 预计 2027年1月」(PRD 4.5.3 #5)；
    /// 预计完成日在今天一年以后时「排队中 · 大于 1 年」，没法预计时「排队中 · 暂时没法预计」。
    public let estimate: String
    /// 面板攒钱队列里的短版预计，如「预计 2月27日」「预计 2027年1月」「大于 1 年」「暂时没法预计」。
    public let shortEstimate: String
    /// 首页用的预计完成，如「2月27日」「2027年1月」，在今天一年以后时为「大于 1 年」；没法预计时为 nil。
    public let finishText: String?
}

extension GoalQueueSection {
    /// 展开时面板目标区最多显示几个目标 (累计中 + 排队中)。
    static let expandedLimit = 3

    /// `active`：累计中目标的卡片，排队中目标的预计完成日从它的预计完成日之后起数。
    init?(state: AppState, active: ActiveGoalCard?, today: Today, holidays: HolidayTable) {
        let queued = state.goals.filter(\.status.isQueued)
        guard let active, !queued.isEmpty else { return nil }
        let shown = Array(queued.prefix(Self.expandedLimit - 1))
        let finishes = AttendanceRule(holidays: holidays).queuedFinishDates(shown, after: active.finish, dailyWage: today.dailyWage, today: today.date)
        let cards = zip(shown, finishes).map { goal, finish in QueuedGoalCard(goal: goal, finish: finish, today: today.date) }
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
    /// `finish` 太远 (在今天一年以后) 时说「大于 1 年」，没法预计 (本月没有应出勤日，日薪为 0) 时说「暂时没法预计」。
    init(goal: Goal, finish: EstimatedFinish, today: LocalDate) {
        id = goal.id
        name = goal.name
        amountText = Format.money(goal.amount)
        switch finish {
        case .date(let day):
            finishText = Format.estimateDate(day, today: today)
            shortEstimate = "预计 \(Format.estimateDate(day, today: today))"
        case .tooFar:
            finishText = ActiveGoalCard.beyondLimit
            shortEstimate = ActiveGoalCard.beyondLimit
        case .unknown:
            finishText = nil
            shortEstimate = ActiveGoalCard.noEstimateShort
        }
        estimate = "排队中 · \(shortEstimate)"
    }
}

extension AttendanceRule {
    /// 排队中目标依次的预计完成日 (PRD 4.5.3 #5)：每个从前一个的预计完成日之后起，
    /// 按当月日薪数 ceil(目标金额 ÷ 日薪) 个应出勤日，跨月、跨年都仍按当月日薪【D7】。
    /// `first` 是排在它们前面那个目标 (累计中) 的预计完成；日薪为 0 时 (PRD 4.3.5 #19) 前一个没法预计，后面的也都没法预计。
    /// 预计完成日晚于 `today` (不是前一个的完成日) 之后 `ActiveGoalCard.estimateDayLimit` 个日历日时太远，不数日期，它和后面的都是太远。
    func queuedFinishDates(_ goals: [Goal], after first: EstimatedFinish, dailyWage: Decimal, today: LocalDate) -> [EstimatedFinish] {
        var previous = first
        return goals.map { goal in
            guard let day = previous.date else { return previous }
            let finish = EstimatedFinish(
                ActiveGoalCard.workDays(for: goal.amount, dailyWage: dailyWage).flatMap { finishDay($0, after: day, from: today) },
                dailyWage: dailyWage
            )
            previous = finish
            return finish
        }
    }
}

extension Format {
    /// 预计完成日：今年内「11月26日」，不在今年「2027年4月」(PRD 4.5.3 #5)。
    static func estimateDate(_ day: LocalDate, today: LocalDate) -> String {
        day.year == today.year ? monthDay(day) : yearMonth(day)
    }

    /// 年月，如「2027年1月」。
    static func yearMonth(_ day: LocalDate) -> String {
        "\(day.year)年\(day.month)月"
    }
}
