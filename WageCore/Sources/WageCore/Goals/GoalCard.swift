import Foundation

/// 面板目标区的展示内容 (PRD F9)，文字和数字已格式化好，外壳原样展示。
public enum GoalCard: Sendable, Equatable {
    /// 队列为空：提示文案「给自己定个目标吧」，点击进入目标管理。
    case empty(String)
    /// 累计中目标。
    case active(ActiveGoalCard)
}

/// 累计中目标的卡片。
public struct ActiveGoalCard: Sendable, Equatable {
    /// 目标编号，与目标管理列表里的同一行一致。
    public let id: Int
    public let name: String
    /// 累计额与目标金额，如「¥3000 / ¥10000」；累计额为负时显示 ¥0 (PRD 4.3.5 #17)。
    public let amountText: String
    /// 进度条比例，0 至 1；累计额为负时为 0 (PRD 4.3.5 #17)，达标后为 1。
    public let progress: Double
    /// 预计完成 (PRD 4.5.3)，如「还需搬砖 7 天 · 2月20日」或「今天就能达成」。
    public let estimate: String
    /// 预计完成日 (今天就能达成时为今天)，排队中目标从它之后起数 (PRD 4.5.3 #5)。
    /// 本月没有应出勤日 (日薪为 0) 时没法预计，为 nil。
    let finishDate: LocalDate?
}

extension GoalCard {
    /// `active`：累计中目标的卡片，没有时队列为空。
    init(active: ActiveGoalCard?) {
        self = active.map(GoalCard.active) ?? .empty("给自己定个目标吧")
    }
}

extension ActiveGoalCard {
    /// 累计中目标的卡片；没有累计中目标时为 nil。
    /// 累计额 = 累计收入 - 起算基准 (PRD 4.5.2)。
    init?(state: AppState, profile: Profile, today: Today, holidays: HolidayTable) {
        guard let current = state.accumulatingGoal else { return nil }
        let income = Ledger.cumulativeIncome(profile: profile, dayRecords: state.dayRecords, today: today, holidays: holidays)
        self.init(goal: current.goal, accumulated: income - current.baseline, today: today, rule: AttendanceRule(holidays: holidays))
    }

    /// `goal` 以累计额 `accumulated` 累计时的卡片；目标管理页也用它预览排队中目标排到第一个时的样子。
    init(goal: Goal, accumulated: Decimal, today: Today, rule: AttendanceRule) {
        let shown = min(max(accumulated, 0), goal.amount)
        id = goal.id
        name = goal.name
        amountText = "\(Format.money(max(accumulated, 0))) / \(Format.money(goal.amount))"
        progress = NSDecimalNumber(decimal: shown / goal.amount).doubleValue
        (estimate, finishDate) = Self.estimate(remaining: goal.amount - accumulated, today: today, rule: rule)
    }

    /// 预计完成 (PRD 4.5.3)：
    /// 今天是应出勤日且未下班时，先扣除今日剩余可赚 (今日上限 - 今日已赚)，扣除后不大于 0 即「今天就能达成」；
    /// 否则 N = 剩余金额 ÷ 当月日薪 向上取整，从明天起数第 N 个应出勤日，跨月仍按当月日薪【D7】。
    private static func estimate(remaining: Decimal, today: Today, rule: AttendanceRule) -> (text: String, finish: LocalDate?) {
        var rest = remaining
        if let earnings = today.earnings, today.status != .offWork {
            rest -= earnings.cap - earnings.earned
        }
        guard rest > 0 else { return ("今天就能达成", today.date) }
        // 本月全部覆盖为不上班时日薪为 0 (PRD 4.3.5 #19)，没法按当月日薪估算。
        guard let days = workDays(for: rest, dailyWage: today.dailyWage) else { return (noEstimate, nil) }
        let finish = rule.attendanceDay(days, after: today.date)
        return ("还需搬砖 \(days) 天 · \(Format.monthDay(finish))", finish)
    }

    /// 攒够 `amount` 需要的应出勤日数 = `amount` ÷ 日薪 向上取整，如 6.5714 → 7。
    /// 先四舍五入到 `noiseScale` 位小数，去掉十进制除法的末位误差 (如 1/7 往返后的 9.000…0003)，免得多算一天。
    /// 当月应出勤日数为 0 (如全部覆盖为不上班) 时日薪为 0 (PRD 4.3.5 #19)，没法估算，为 nil。
    static func workDays(for amount: Decimal, dailyWage: Decimal) -> Int? {
        guard dailyWage > 0 else { return nil }
        var quotient = amount / dailyWage
        var cleaned = Decimal()
        NSDecimalRound(&cleaned, &quotient, noiseScale, .plain)
        var result = Decimal()
        NSDecimalRound(&result, &cleaned, 0, .up)
        return NSDecimalNumber(decimal: result).intValue
    }

    /// 日薪为 0 时累计中目标的预计文案。
    static let noEstimate = "本月没有要上班的日子，暂时没法预计"

    /// 算天数前保留的小数位，远小于 1 天，又远大于十进制运算的末位误差。
    private static let noiseScale = 10
}

extension AttendanceRule {
    /// `day` 之后 (不含当天) 的第 `count` 个应出勤日，`count` 至少为 1。
    func attendanceDay(_ count: Int, after day: LocalDate) -> LocalDate {
        var found = 0
        var date = day
        while found < count {
            date = date.adding(days: 1)
            if isAttendanceDay(date) { found += 1 }
        }
        return date
    }
}

extension Format {
    /// 日期，如「2月20日」；给了 `reference` 且不在同一年时带年份，如「2026年12月30日」。
    static func monthDay(_ day: LocalDate, relativeTo reference: LocalDate? = nil) -> String {
        let year = reference.map { $0.year == day.year } ?? true ? "" : "\(day.year)年"
        return "\(year)\(day.month)月\(day.day)日"
    }
}
