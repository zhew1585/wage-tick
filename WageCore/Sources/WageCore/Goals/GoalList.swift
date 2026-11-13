import Foundation

/// 目标管理页 (PRD F8，页面 P3) 的目标列表，分两组，文字已格式化好。
/// 攒钱队列在目标页，已完成在「已到手」页 (大胆版设计稿「目标-已到手」)。
public struct GoalList: Sendable, Equatable {
    /// 攒钱队列：全部未完成目标，按队列顺序；第一个是累计中，其余排队中。整组可拖动排序【D6】。
    public let queue: [QueueGoalRow]
    /// 已完成：按完成时间倒序，沉底，不参与排序、不能编辑 (AC-GOAL-10)。
    public let completed: [CompletedGoalRow]
    /// 队列里最后一个目标的预计完成，如「全部攒完 预计 2027年4月」；队列为空或没法预计 (日薪为 0) 时为 nil。
    public let queueFinishText: String?
    /// 已完成的总结，如「共 ¥9594 · 搬砖 9.6 天」(搬砖天数 = 总额 ÷ 当前日薪，日薪为 0 时只有「共 ¥9594」)；没有已完成时为 nil。
    public let completedSummary: String?

    public init(queue: [QueueGoalRow], completed: [CompletedGoalRow], queueFinishText: String? = nil, completedSummary: String? = nil) {
        self.queue = queue
        self.completed = completed
        self.queueFinishText = queueFinishText
        self.completedSummary = completedSummary
    }

    /// 没有任何目标。
    public static let empty = GoalList(queue: [], completed: [])

    public var isEmpty: Bool { queue.isEmpty && completed.isEmpty }

    /// 已完成按达成年份分组，年份倒序，组内仍按完成时间倒序。
    public var completedYears: [CompletedGoalYear] {
        let years = completed.map(\.year).reduce(into: [Int]()) { years, year in
            if years.last != year { years.append(year) }
        }
        return years.map { year in
            let rows = completed.filter { $0.year == year }
            let total = rows.reduce(Decimal(0)) { $0 + $1.amount }
            return CompletedGoalYear(year: year, summary: "\(rows.count) 件 · \(Format.money(total))", rows: rows)
        }
    }
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
    /// 按眼下的位置排队时的预计，同面板「排队中 · 预计 11月26日」「排队中 · 暂时没法预计」；
    /// 第一行 (累计中) 是 `asFirst.estimate`。
    public let estimate: String
}

/// 已完成的一行，冻结，只能删除。
public struct CompletedGoalRow: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    /// 目标金额，如「¥500」。
    public let amountText: String
    /// 完成时刻，如「2月11日 15:00 达成」，不在今年时带年份「2026年12月30日 15:00 达成」。
    public let completedText: String
    /// 达成那天的年份，已到手页按它分组。
    public let year: Int
    /// 达成日期，如「10月28日 到手」(已按年分组，不带年份)。
    public let receivedText: String
    /// 相当于搬砖几天 = 目标金额 ÷ 当前日薪，保留 1 位小数，如「≈ 搬砖 1.9 天」；日薪为 0 时为 nil。
    public let workDaysText: String?
    /// 目标金额，按年小计用。
    public let amount: Decimal

    public init(
        id: Int, name: String, amount: Decimal, completedText: String, year: Int, receivedText: String, workDaysText: String?
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.amountText = Format.money(amount)
        self.completedText = completedText
        self.year = year
        self.receivedText = receivedText
        self.workDaysText = workDaysText
    }
}

/// 已到手页的一年：年份、小计 (如「7 件 · ¥9594」) 与这一年达成的目标。
public struct CompletedGoalYear: Sendable, Equatable, Identifiable {
    public let year: Int
    public let summary: String
    public let rows: [CompletedGoalRow]

    public var id: Int { year }
}

extension GoalList {
    /// 攒钱队列按 `AppState.goals` 里未完成目标的先后 (累计中总在排队中之前)；已完成按完成时间倒序。
    init(state: AppState, profile: Profile, today: Today, now: Moment, holidays: HolidayTable) {
        let accumulated = state.accumulatingGoal.map { current in
            Ledger.cumulativeIncome(profile: profile, dayRecords: state.dayRecords, today: today, holidays: holidays) - current.baseline
        } ?? 0
        let rule = AttendanceRule(holidays: holidays)
        let goals = state.goals.filter { !$0.status.isCompleted }
        let cards = goals.map { ActiveGoalCard(goal: $0, accumulated: accumulated, today: today, rule: rule) }
        let finishes = cards.first.map { first in
            [first.finishDate] + rule.queuedFinishDates(Array(goals.dropFirst()), after: first.finishDate, dailyWage: today.dailyWage)
        } ?? []
        let queue = zip(goals, zip(cards, finishes)).enumerated().map { index, item in
            let (goal, (card, finish)) = item
            return QueueGoalRow(
                id: goal.id, name: goal.name,
                amountText: Format.money(goal.amount), amountInput: Format.editable(goal.amount),
                asFirst: card,
                estimate: index == 0 ? card.estimate : QueuedGoalCard(goal: goal, finish: finish, today: today.date).estimate
            )
        }
        let completed = state.goals.compactMap { goal -> (Goal, Date)? in
            if case .completed(let at) = goal.status { (goal, at) } else { nil }
        }
        let done = completed.sorted { $0.1 > $1.1 }.map { goal, at in
            let moment = Moment(date: at, timeZone: now.timeZone)
            return CompletedGoalRow(
                id: goal.id, name: goal.name, amount: goal.amount,
                completedText: "\(Format.monthDay(moment.localDate, relativeTo: today.date)) \(Format.time(moment)) 达成",
                year: moment.localDate.year,
                receivedText: "\(Format.monthDay(moment.localDate)) 到手",
                workDaysText: Self.workDays(goal.amount, dailyWage: today.dailyWage).map { "≈ 搬砖 \($0) 天" }
            )
        }
        self.init(
            queue: queue,
            completed: done,
            queueFinishText: finishes.last.flatMap { $0 }.map { "全部攒完 预计 \(Format.estimateDate($0, today: today.date))" },
            completedSummary: Self.summary(done, dailyWage: today.dailyWage)
        )
    }

    /// 「共 ¥9594 · 搬砖 9.6 天」；日薪为 0 时只有「共 ¥9594」；没有已完成时为 nil。
    private static func summary(_ rows: [CompletedGoalRow], dailyWage: Decimal) -> String? {
        guard !rows.isEmpty else { return nil }
        let total = rows.reduce(Decimal(0)) { $0 + $1.amount }
        let money = "共 \(Format.money(total))"
        return workDays(total, dailyWage: dailyWage).map { "\(money) · 搬砖 \($0) 天" } ?? money
    }

    /// `amount` 相当于搬砖几天，保留 1 位小数，如「1.9」「1.0」；日薪为 0 时为 nil。
    private static func workDays(_ amount: Decimal, dailyWage: Decimal) -> String? {
        guard dailyWage > 0 else { return nil }
        let text = NSDecimalNumber(decimal: Format.round(amount / dailyWage, scale: 1)).stringValue
        return text.contains(".") ? text : "\(text).0"
    }
}
