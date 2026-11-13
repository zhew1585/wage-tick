import Foundation

/// 今日概览面板应展示的全部文字 (PRD F4)，数字已按 D9 格式化好，外壳原样展示，不做任何计算或拼接。
public struct TodayPanel: Sendable, Equatable {
    /// 顶部日期，如「2月11日 周三」。
    public let dateText: String
    /// 顶部时间，带秒，如「15:07:30」。
    public let timeText: String
    /// 顶部状态标签，如「上班中」；白干计时中为「白干中」(只是展示，不是日状态)。
    public let statusLabel: String
    public let body: Body
    /// 面板顶部的提示条，按顺序展示，没有时为空：节假日数据缺失 (AC-HOME-08)、本月没有要上班的日子 (AC-HOME-09)。
    public let notices: [String]
    /// 「今天扣钱了」入口 (F5)；休息日为 nil，不显示按钮 (AC-FINE-07)。
    public let deductionEntry: DeductionEntry?
    /// 白干计时按钮 (F7)：已下班为「我还没走」、休息日为「被迫营业」、计时中为「终于下班了」；不可用时为 nil。
    public let unpaidWorkButton: UnpaidWorkButton?
    /// 目标区 (PRD F9)。
    public let goal: GoalCard
    /// 目标区里累计中目标下方的排队部分 (PRD F9)；没有排队中目标时为 nil。面板只用其中的 `upcoming`，展开收起的字段保留未用。
    public let goalQueue: GoalQueueSection?
    /// 目标区标题右侧的目标总数 (累计中 + 全部排队中，可能多于列出的 3 个)，如「3 个目标」；没有未完成目标时为 nil。
    public let goalCountText: String?
    /// 底部入口栏右侧的距发薪 (issue #20)；没设发薪日时为 nil，不显示。
    public let payday: PaydayFooter?
    /// 头图里小牛此刻的场景 (与悬浮小牛同一套判定)，决定头图配色与小牛姿势；不受悬浮小牛开关影响。
    public let cowScene: CowScene
    /// 头图里小牛头顶的气泡 (与悬浮小牛同一句)。
    public let cowBubble: FloatingCowBubble
    /// 大胆版的进度格 (每格 1 小时)；休息日没在白干时为 nil。
    public let blocks: HourBlocks?

    public enum Body: Sendable, Equatable {
        /// 应出勤日：未上班、上班中、干饭中、请假中、已下班。
        case attendance(AttendancePanel)
        /// 休息日。
        case rest(RestPanel)
        /// 白干计时中 (我还没走或被迫营业)，含前一天开始、跨过零点还在计时。
        case unpaidWork(UnpaidWorkPanel)
    }
}

/// 休息日的面板内容 (PRD F4)。
public struct RestPanel: Sendable, Equatable {
    /// 如「今天休息」。
    public let headline: String
    /// 标题下方的一句说明，如「不搬砖，不计钱。」；全天请假时为 nil (请假可能扣薪)。
    public let tagline: String?
    /// 标题下方的下一个应出勤日，如「下一个上班日 11月10日 周一」；一年内都没有时为 nil。
    public let nextAttendanceText: String?
    /// 统计行：本月已上班 (如「5/20 天」)、本月累计、距离周末。
    public let stats: [StatItem]

    public init(headline: String, tagline: String?, nextAttendanceText: String?, stats: [StatItem]) {
        self.headline = headline
        self.tagline = tagline
        self.nextAttendanceText = nextAttendanceText
        self.stats = stats
    }
}

/// 统计行里的一项，如「本月累计 ¥9571.43」。
public struct StatItem: Sendable, Equatable {
    public let title: String
    public let value: String
    public let tone: Tone

    /// 值的颜色。
    public enum Tone: Sendable, Equatable {
        /// 默认色。
        case plain
        /// 醒目显示 (accent 色)：距离周末。
        case accent
        /// money 绿：今天发薪。
        case money
    }

    /// 醒目显示 (accent 色)，即 `tone == .accent`。
    public var isHighlighted: Bool { tone == .accent }

    public init(title: String, value: String, tone: Tone = .plain) {
        self.title = title
        self.value = value
        self.tone = tone
    }
}

/// 应出勤日的面板内容。
public struct AttendancePanel: Sendable, Equatable {
    /// 主数字，带 ¥，4 位小数：今日已赚。
    public let headline: String
    /// 主数字下方一行小字：上班中等为「满勤日薪 ¥1000 · 时薪 ¥142.86」，已下班见 `UnpaidWorkToday.offWorkCaption`；
    /// 有扣款时末尾接「 · 扣款 −¥50」(统计行里不再有今日扣款)。
    public let caption: String
    public let progress: WorkProgress?
    /// 统计行，如距离下班倒计时、本月累计。
    public let stats: [StatItem]
    /// 今天的扣钱明细，按记录先后 (AC-FINE-04)。
    public let deductions: [DeductionItem]
    /// 当日扣款超过日薪时的提示 (PRD 4.3.5 #6)，否则为 nil。
    public let notice: String?
}

/// 工作进度区。
public struct WorkProgress: Sendable, Equatable {
    /// 如「已工作 4 / 7 小时」「已工作 5.1 / 7 小时」：小时数保留 1 位小数，已工作向下取。
    public let label: String
    /// 如「57.14%」。
    public let percent: String
    /// 进度条各段，饭点与落在中间的请假显示为段与段之间的间隔。
    public let segments: [ProgressSegment]
    /// 进度条下方左端，当日计划上班，如「上班 10:00」。
    public let startText: String
    /// 进度条下方右端，当日计划下班，如「下班 18:00」(请了后半天为「下班 12:00」)。
    public let endText: String
}

/// 进度条的一段 (只用于绘制)。
public struct ProgressSegment: Sendable, Equatable {
    /// 本段占整条进度条的宽度比例，各段之和为 1。
    public let share: Double
    /// 本段已走过的比例，0 至 1。
    public let filled: Double

    public init(share: Double, filled: Double) {
        self.share = share
        self.filled = filled
    }
}

extension TodayPanel {
    init(today: Today, now: Moment, holidays: HolidayTable, goal: GoalCard, goalQueue: GoalQueueSection?, goalCount: Int) {
        dateText = Format.date(today.date, relativeTo: today.date)
        timeText = Format.clock(now)
        statusLabel = today.unpaidWork.isRunning ? "白干中" : today.status.label
        notices = [holidays.missingNotice(on: today.date), noAttendanceNotice(today.date, holidays: holidays)].compactMap { $0 }
        deductionEntry = today.settlement.map { DeductionEntry(settlement: $0) }
        unpaidWorkButton = UnpaidWorkButton(today: today)
        self.goal = goal
        self.goalQueue = goalQueue
        goalCountText = goalCount > 0 ? "\(goalCount) 个目标" : nil
        payday = today.paydayCountdown.map(PaydayFooter.init)
        let scene = CowScene(today: today)
        cowScene = scene
        cowBubble = FloatingCowBubble(scene: scene, today: today, now: now)
        let regular = Self.regularBody(today: today, now: now, holidays: holidays)
        blocks = today.unpaidWork.running.map { HourBlocks(today: today, running: $0) } ?? HourBlocks(today: today, now: now)
        if let running = today.unpaidWork.running {
            body = .unpaidWork(UnpaidWorkPanel(today: today, running: running, now: now, todayStats: regular.stats))
        } else {
            body = regular
        }
    }

    /// 不在白干计时时的主体：应出勤日 (有当日计划) 或休息日 (含全天请假)。
    private static func regularBody(today: Today, now: Moment, holidays: HolidayTable) -> Body {
        guard let earnings = today.earnings, let plan = today.plan, let settlement = today.settlement else {
            return .rest(RestPanel(today: today, holidays: holidays))
        }
        return .attendance(AttendancePanel(today: today, earnings: earnings, settlement: settlement, plan: plan, now: now))
    }
}

extension TodayPanel {
    /// 菜单栏菜单最上面的今日信息 (issue #18)：同统计行的三项；菜单栏是「仅图标」、今天还没下班时，最前面多一行今日已赚
    /// (菜单栏上看不到这个数；已下班的统计行里已有今日结算)。设了发薪日时距离周末下面多一行距离发薪 (issue #20)。
    func menuInfo(today: Today, menuBarMode: MenuBarMode) -> [StatItem] {
        let stats = Self.insertingPayday(today.paydayCountdown, into: body.stats, after: today.restCountdown)
        guard menuBarMode == .iconOnly, case .attendance = body, today.status != .offWork, let earnings = today.earnings else {
            return stats
        }
        return [StatItem(title: "今日已赚", value: Format.money(earnings.earned))] + stats
    }

    /// 距离发薪插在距离周末那项后面；统计行里没有距离周末 (一年内都没有休息日) 时放最后。
    private static func insertingPayday(
        _ payday: PaydayCountdown?, into stats: [StatItem], after rest: RestCountdown?
    ) -> [StatItem] {
        guard let payday else { return stats }
        let restIndex = rest.flatMap { stats.firstIndex(of: .restCountdown($0)) }
        let index = restIndex.map { $0 + 1 } ?? stats.endIndex
        return stats[..<index] + [.paydayCountdown(payday)] + stats[index...]
    }
}

extension TodayPanel.Body {
    var stats: [StatItem] {
        switch self {
        case .attendance(let panel): panel.stats
        case .rest(let panel): panel.stats
        case .unpaidWork(let panel): panel.stats
        }
    }
}

extension AttendancePanel {
    init(today: Today, earnings: Earnings, settlement: DaySettlement, plan: DayPlan, now: Moment) {
        let monthToDate = StatItem(title: "本月累计", value: Format.money(today.monthToDate))
        // 已下班时今日已赚 = 今日上限 = 今日结算 (PRD 4.3.4)。
        headline = Format.rollingMoney(earnings.earned)
        let deduction = Self.deductionCaption(today: today, settlement: settlement)
        if today.status == .offWork {
            caption = today.unpaidWork.offWorkCaption + deduction
            progress = nil
            stats = Self.offWorkStats(today: today, earnings: earnings, settlement: settlement)
        } else {
            // 按天算没有「满勤」一说，只写日薪。
            let wageTitle = today.payBasis == .daily ? "日薪" : "满勤日薪"
            caption = "\(wageTitle) \(Format.money(today.dailyWage)) · 时薪 \(Format.money(today.hourlyWage))" + deduction
            progress = WorkProgress(plan: plan, progress: earnings.progress, now: now)
            stats = [
                StatItem(title: "距离下班", value: Self.countdownText(today: today, plan: plan, now: now)),
                Self.middleStat(today: today, settlement: settlement),
                monthToDate,
            ]
        }
        deductions = settlement.deductions.map(DeductionItem.init)
        notice = Self.notice(settlement)
    }

    /// 距离下班：未上班时还没开始倒计时，显示「-」；上班中、干饭中、请假中为计划下班前的剩余时间。
    static func countdownText(today: Today, plan: DayPlan, now: Moment) -> String {
        today.status == .notStarted ? "-" : Format.countdown(from: now.date, to: plan.end)
    }

    /// 已下班的统计行：今日结算、距离周末、本月累计。白干计时中的统计行与它相同 (F4 第 5 条)。
    static func offWorkStats(today: Today, earnings: Earnings, settlement: DaySettlement) -> [StatItem] {
        let settled = StatItem(title: "今日结算", value: Format.money(earnings.cap))
        let monthToDate = StatItem(title: "本月累计", value: Format.money(today.monthToDate))
        return [settled, middleStat(today: today, settlement: settlement), monthToDate]
    }

    /// 统计行中间一项：距离周末 (V1.13 起替代今日扣款)；一年内都没有休息日时退回今日扣款。
    private static func middleStat(today: Today, settlement: DaySettlement) -> StatItem {
        today.restCountdown.map(StatItem.restCountdown) ?? deductionStat(settlement)
    }

    /// 主数字下方小字末尾的扣款，如「 · 扣款 −¥50」：只在有扣款、且统计行里放的是距离周末时出现。
    private static func deductionCaption(today: Today, settlement: DaySettlement) -> String {
        guard today.restCountdown != nil, settlement.deductionTotal > 0 else { return "" }
        return " · 扣款 \(Format.deduction(settlement.deductionTotal))"
    }
}

extension RestPanel {
    init(today: Today, holidays: HolidayTable) {
        // 全天请假按休息日呈现，但标题为「今天请假」(AC-HOME-07)。
        let isLeave = today.leave != nil
        let monthDays = AttendanceRule(holidays: holidays).attendanceDayCount(in: today.date.yearMonth)
        self.init(
            headline: isLeave ? "今天请假" : "今天休息",
            tagline: isLeave ? nil : "不搬砖，不计钱。",
            nextAttendanceText: today.nextAttendanceDay.map { "下一个上班日 \(Format.date($0, relativeTo: today.date))" },
            stats: [
                StatItem(title: "本月已上班", value: "\(today.attendedDays)/\(monthDays) 天"),
                StatItem(title: "本月累计", value: Format.money(today.monthToDate)),
            ] + [today.restCountdown.map(StatItem.restCountdown)].compactMap { $0 }
        )
    }
}

extension WorkProgress {
    init(plan: DayPlan, progress: Decimal, now moment: Moment) {
        let now = moment.date
        let elapsedMilliseconds = plan.elapsedMilliseconds(at: now)
        let total = Format.workHours(milliseconds: plan.effectiveMilliseconds)
        // 走满了就和应有时长显示得一样，否则向下取 1 位。
        let elapsed = elapsedMilliseconds >= plan.effectiveMilliseconds
            ? total
            : Format.workHours(milliseconds: elapsedMilliseconds, roundingDown: true)
        label = "已工作 \(elapsed) / \(total) 小时"
        percent = Format.percent(progress)
        // 计划里没有有效工时时没有任何一段，`barLength` 不会被用作除数。
        let barLength = plan.workPeriods.map(\.length).reduce(0, +)
        segments = plan.workPeriods.map { period in
            let walked = min(max(now.timeIntervalSince(period.start), 0), period.length)
            return ProgressSegment(share: period.length / barLength, filled: walked / period.length)
        }
        startText = "上班 \(Format.time(Moment(date: plan.start, timeZone: moment.timeZone)))"
        endText = "下班 \(Format.time(Moment(date: plan.end, timeZone: moment.timeZone)))"
    }
}

extension DayStatus {
    /// 面板顶部的状态标签文案 (PRD 4.3.3)。
    var label: String {
        switch self {
        case .restDay: "休息日"
        case .notStarted: "未上班"
        case .working: "上班中"
        case .lunchBreak: "干饭中"
        case .onLeave: "请假中"
        case .offWork: "已下班"
        }
    }
}

/// 当月应出勤日数为 0 (如全部被覆盖为不上班) 时的提示 (PRD 4.3.5 #19、AC-HOME-09)；否则为 nil。
private func noAttendanceNotice(_ today: LocalDate, holidays: HolidayTable) -> String? {
    AttendanceRule(holidays: holidays).attendanceDayCount(in: today.yearMonth) == 0 ? "本月没有要上班的日子" : nil
}
