import Foundation

/// 目标管理页 (PRD F8，页面 P3) 的目标列表，分两组，文字已格式化好。
public struct GoalList: Sendable, Equatable {
    /// 攒钱队列：全部未完成目标，按队列顺序；第一个是累计中，其余排队中。整组可拖动排序【D6】。
    public let queue: [QueueGoalRow]
    /// 已完成：按完成时间倒序，沉底，不参与排序、不能编辑 (AC-GOAL-10)。
    public let completed: [CompletedGoalRow]

    public init(queue: [QueueGoalRow], completed: [CompletedGoalRow]) {
        self.queue = queue
        self.completed = completed
    }

    /// 没有任何目标。
    public static let empty = GoalList(queue: [], completed: [])

    public var isEmpty: Bool { queue.isEmpty && completed.isEmpty }
}

/// 攒钱队列里的一行 (累计中或排队中)，可编辑名称和金额。
public struct QueueGoalRow: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    /// 目标金额，如「¥3000」，排队中的行展示它。
    public let amountText: String
    /// 目标金额，截掉末尾 0，如「3000.5」，编辑时直接填进输入框。
    public let amountInput: String
    /// 这个目标排在攒钱队列第一个 (累计中) 时的卡片：进度、累计额 / 目标金额、预计完成。
    /// 第一行就是此刻的累计中目标，与面板目标区同一份；其余行是拖到最前时的即时预览，
    /// 累计额 = 当前已累计的钱 (换人时转过去【D6】)，已达标的松手即完成。
    public let asFirst: ActiveGoalCard
}

/// 已完成的一行，冻结，只能删除。
public struct CompletedGoalRow: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    /// 目标金额，如「¥500」。
    public let amountText: String
    /// 如「2月11日达成」，不在今年时带年份「2026年12月30日达成」。
    public let completedText: String

    public init(id: Int, name: String, amountText: String, completedText: String) {
        self.id = id
        self.name = name
        self.amountText = amountText
        self.completedText = completedText
    }
}

extension GoalList {
    /// 攒钱队列按 `AppState.goals` 里未完成目标的先后 (累计中总在排队中之前)；已完成按完成时间倒序。
    init(state: AppState, profile: Profile, today: Today, now: Moment, holidays: HolidayTable) {
        let accumulated = state.accumulatingGoal.map { current in
            Ledger.cumulativeIncome(profile: profile, dayRecords: state.dayRecords, today: today, holidays: holidays) - current.baseline
        } ?? 0
        let rule = AttendanceRule(holidays: holidays)
        let queue = state.goals.filter { !$0.status.isCompleted }.map { goal in
            QueueGoalRow(
                id: goal.id, name: goal.name,
                amountText: Format.money(goal.amount), amountInput: Format.trimmed(goal.amount),
                asFirst: ActiveGoalCard(goal: goal, accumulated: accumulated, today: today, rule: rule)
            )
        }
        let completed = state.goals.compactMap { goal -> (Goal, Date)? in
            if case .completed(let at) = goal.status { (goal, at) } else { nil }
        }
        let done = completed.sorted { $0.1 > $1.1 }.map { goal, at in
            let day = Moment(date: at, timeZone: now.timeZone).localDate
            return CompletedGoalRow(
                id: goal.id, name: goal.name, amountText: Format.money(goal.amount),
                completedText: "\(Format.monthDay(day, relativeTo: today.date))达成"
            )
        }
        self.init(queue: queue, completed: done)
    }
}
