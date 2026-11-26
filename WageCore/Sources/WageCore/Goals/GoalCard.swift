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
    /// 单独的累计额，如「¥3000」，与 `amountText` 前半段相同，供大号数字分开排版。
    public let accumulatedText: String
    /// 单独的目标金额，如「¥10000」。
    public let targetText: String
    /// 进度条比例，0 至 1；累计额为负时为 0 (PRD 4.3.5 #17)，达标后为 1。
    public let progress: Double
    /// 进度百分比，固定 2 位小数，如「30.00%」「28.57%」；与 `progress` 同样夹在 0% 至 100%。
    public let percentText: String
    /// 预计完成 (PRD 4.5.3)，如「还需搬砖 7 天 · 2月20日」或「今天就能达成」。
    public let estimate: String
    /// 面板攒钱队列卡片里的短版预计，和金额挤在一行：如「还需 7 天 · 2月20日」「今天就能达成」「还需大于 1 年」「暂时没法预计」。
    public let shortEstimate: String
    /// 首页用的预计完成：今年内如「2月20日」，不在今年如「2027年1月」；今天就能达成 (含已经攒够) 为「今天」；
    /// 预计完成日在今天一年以后时为「大于 1 年」；本月没有应出勤日 (日薪为 0) 时没法预计，为 nil。
    public let finishText: String?
    /// 预计完成 (今天就能达成时为今天)，排队中目标从它之后起数 (PRD 4.5.3 #5)。
    let finish: EstimatedFinish
}

/// 一个目标的预计完成：有日期、太远 (晚于今天之后 `ActiveGoalCard.estimateDayLimit` 个日历日) 或没法预计 (日薪为 0)。
enum EstimatedFinish: Sendable, Equatable {
    case date(LocalDate)
    case tooFar
    case unknown

    /// 预计完成日，太远或没法预计时为 nil。
    var date: LocalDate? {
        if case .date(let day) = self { day } else { nil }
    }

    /// 按日薪 `dailyWage` 数出的预计完成日 `day`；为 nil 时日薪大于 0 说明太远，否则没法预计。
    init(_ day: LocalDate?, dailyWage: Decimal) {
        self = day.map(Self.date) ?? (dailyWage > 0 ? .tooFar : .unknown)
    }
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
        accumulatedText = Format.money(max(accumulated, 0))
        targetText = Format.money(goal.amount)
        amountText = "\(accumulatedText) / \(targetText)"
        let ratio = shown / goal.amount
        progress = NSDecimalNumber(decimal: ratio).doubleValue
        percentText = Format.percent(ratio)
        (estimate, shortEstimate, finishText, finish) = Self.estimate(remaining: goal.amount - accumulated, today: today, rule: rule)
    }

    /// 预计完成 (PRD 4.5.3)：
    /// 今天是应出勤日且未下班时，先扣除今日剩余可赚 (今日上限 - 今日已赚)，扣除后不大于 0 即「今天就能达成」；
    /// 否则 N = 剩余金额 ÷ 当月日薪 向上取整，从明天起数第 N 个应出勤日，跨月仍按当月日薪【D7】。
    /// 预计完成日晚于今天之后 `estimateDayLimit` 个日历日 (含大到算不出天数) 时只说「还需搬砖大于 1 年」。
    /// 返回完整文案、面板用的短版文案、首页用的只有日期的预计完成与预计完成。
    private static func estimate(
        remaining: Decimal, today: Today, rule: AttendanceRule
    ) -> (text: String, short: String, finishText: String?, finish: EstimatedFinish) {
        // 只有目标管理页的预览会走到：真正累计中的目标达标即完成【D6】。
        guard remaining > 0 else { return (reachedPreview, reachedPreview, finishToday, .date(today.date)) }
        var rest = remaining
        if let earnings = today.earnings, today.status != .offWork {
            rest -= earnings.cap - earnings.earned
        }
        guard rest > 0 else { return (reachedToday, reachedToday, finishToday, .date(today.date)) }
        let days = workDays(for: rest, dailyWage: today.dailyWage)
        switch EstimatedFinish(days.flatMap { rule.finishDay($0, after: today.date, from: today.date) }, dailyWage: today.dailyWage) {
        case .unknown:
            // 本月全部覆盖为不上班时日薪为 0 (PRD 4.3.5 #19)，没法按当月日薪估算。
            return (noEstimate, noEstimateShort, nil, .unknown)
        case .tooFar:
            return ("还需搬砖\(beyondLimit)", "还需\(beyondLimit)", beyondLimit, .tooFar)
        case .date(let finish):
            return estimate(days: days ?? 0, finish: finish, today: today.date)
        }
    }

    /// 还需 `days` 个应出勤日、预计 `finish` 完成时的文案与预计完成。
    private static func estimate(
        days: Decimal, finish: LocalDate, today: LocalDate
    ) -> (text: String, short: String, finishText: String?, finish: EstimatedFinish) {
        let count = NSDecimalNumber(decimal: days).stringValue
        let date = Format.monthDay(finish)
        return ("还需搬砖 \(count) 天 · \(date)", "还需 \(count) 天 · \(date)", Format.estimateDate(finish, today: today), .date(finish))
    }

    /// 攒够 `amount` 需要的应出勤日数 = `amount` ÷ 日薪 向上取整，如 6.5714 → 7；结果是整数，但可能大到放不进 `Int`。
    /// 先四舍五入到 `noiseScale` 位小数，去掉十进制除法的末位误差 (如 1/7 往返后的 9.000…0003)，免得多算一天。
    /// 当月应出勤日数为 0 (如全部覆盖为不上班) 时日薪为 0 (PRD 4.3.5 #19)，没法估算，为 nil；大到十进制也算不出时同样为 nil。
    static func workDays(for amount: Decimal, dailyWage: Decimal) -> Decimal? {
        guard dailyWage > 0 else { return nil }
        var quotient = amount / dailyWage
        var cleaned = Decimal()
        NSDecimalRound(&cleaned, &quotient, noiseScale, .plain)
        var result = Decimal()
        NSDecimalRound(&result, &cleaned, 0, .up)
        return result.isNaN ? nil : result
    }

    /// 预计完成日最多看到今天之后多少个日历日 (含这一天)，即 1 年；再远只说「大于 1 年」，不数日期，
    /// 逐天数因此最多走这么多步，金额极大或日薪极小时也不会卡死。
    static let estimateDayLimit = 365

    /// 预计完成日晚于今天之后 `estimateDayLimit` 个日历日时的说法，累计中前面接「还需搬砖」「还需」，排队中接「排队中 · 」。
    static let beyondLimit = "大于 1 年"

    /// 排队中目标拖到第一个时已攒够：松手即完成【D6】。
    static let reachedPreview = "已经攒够，排到第一个就达成"

    /// 今天下班前就能攒够时的预计文案。
    static let reachedToday = "今天就能达成"

    /// 今天就能达成时首页的预计完成。
    static let finishToday = "今天"

    /// 日薪为 0 时累计中目标的预计文案。
    static let noEstimate = "本月没有要上班的日子，暂时没法预计"

    /// 日薪为 0 时的短版预计，面板和排队中目标用。
    static let noEstimateShort = "暂时没法预计"

    /// 算天数前保留的小数位，远小于 1 天，又远大于十进制运算的末位误差。
    private static let noiseScale = 10
}

extension AttendanceRule {
    /// `day` 之后 (不含当天) 的第 `days` 个应出勤日；晚于 `today` 之后 `ActiveGoalCard.estimateDayLimit` 个日历日时太远，为 nil。
    /// `days` 本身超过上限时一定太远，不用数。
    func finishDay(_ days: Decimal, after day: LocalDate, from today: LocalDate) -> LocalDate? {
        guard days <= Decimal(ActiveGoalCard.estimateDayLimit) else { return nil }
        return attendanceDay(NSDecimalNumber(decimal: days).intValue, after: day, through: today.adding(days: ActiveGoalCard.estimateDayLimit))
    }

    /// `day` 之后 (不含当天) 的第 `count` 个应出勤日，`count` 至少为 1；数过 `last` 还没数到时为 nil。
    func attendanceDay(_ count: Int, after day: LocalDate, through last: LocalDate) -> LocalDate? {
        var found = 0
        var date = day
        while found < count {
            date = date.adding(days: 1)
            guard date <= last else { return nil }
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
