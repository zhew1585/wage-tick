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

    public enum Body: Sendable, Equatable {
        /// 应出勤日：未上班、上班中、午休中、已下班。
        case attendance(AttendancePanel)
        /// 休息日。
        case rest(RestPanel)
        /// 白干计时中 (我还没走或被迫营业)。
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
    /// 统计行：本月已上班 (如「5/20 天」)、本月累计。
    public let stats: [StatItem]

    public init(headline: String, tagline: String?, nextAttendanceText: String?, stats: [StatItem]) {
        self.headline = headline
        self.tagline = tagline
        self.nextAttendanceText = nextAttendanceText
        self.stats = stats
    }
}

/// 统计行里的一项，如「本月累计 ¥9571.4286」。
public struct StatItem: Sendable, Equatable {
    public let title: String
    public let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

/// 应出勤日的面板内容。
public struct AttendancePanel: Sendable, Equatable {
    /// 主数字，带 ¥，4 位小数：今日已赚。
    public let headline: String
    /// 主数字下方一行小字：上班中等为「满勤日薪 ¥1000 · 时薪 ¥142.8571」，已下班见 `UnpaidWorkToday.offWorkCaption`。
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
    /// 进度条各段，午休显示为段与段之间的间隔。
    public let segments: [ProgressSegment]
    /// 进度条下方左端，当日计划上班，如「上班 10:00」。
    public let startText: String
    /// 进度条下方右端，当日计划下班，如「下班 18:00」(下午假为「下班 12:00」)。
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
        if today.unpaidWork.isRunning {
            body = .unpaidWork(UnpaidWorkPanel(today: today, now: now))
            return
        }
        guard let earnings = today.earnings, let plan = today.plan, let settlement = today.settlement else {
            body = .rest(RestPanel(today: today, holidays: holidays))
            return
        }
        body = .attendance(AttendancePanel(today: today, earnings: earnings, settlement: settlement, plan: plan, now: now))
    }
}

extension AttendancePanel {
    init(today: Today, earnings: Earnings, settlement: DaySettlement, plan: DayPlan, now: Moment) {
        let monthToDate = StatItem(title: "本月累计", value: Format.money(today.monthToDate))
        // 已下班时今日已赚 = 今日上限 = 今日结算 (PRD 4.3.4)。
        headline = Format.rollingMoney(earnings.earned)
        if today.status == .offWork {
            caption = today.unpaidWork.offWorkCaption
            progress = nil
            stats = Self.offWorkStats(today: today, earnings: earnings, settlement: settlement)
        } else {
            caption = "满勤日薪 \(Format.money(today.dailyWage)) · 时薪 \(Format.money(today.hourlyWage))"
            progress = WorkProgress(plan: plan, progress: earnings.progress, now: now)
            stats = [
                StatItem(title: "距离下班", value: Self.countdownText(today: today, plan: plan, now: now)),
                Self.deductionStat(settlement),
                monthToDate,
            ]
        }
        deductions = settlement.deductions.map(DeductionItem.init)
        notice = Self.notice(settlement)
    }

    /// 距离下班：未上班时还没开始倒计时，显示「-」；上班中、午休中为计划下班前的剩余时间。
    static func countdownText(today: Today, plan: DayPlan, now: Moment) -> String {
        today.status == .notStarted ? "-" : Format.countdown(from: now.date, to: plan.end)
    }

    /// 已下班的统计行：今日结算、今日扣款 (没有时 ¥0)、本月累计。白干计时中的统计行与它相同 (F4 第 5 条)。
    static func offWorkStats(today: Today, earnings: Earnings, settlement: DaySettlement) -> [StatItem] {
        let settled = StatItem(title: "今日结算", value: Format.money(earnings.cap))
        let monthToDate = StatItem(title: "本月累计", value: Format.money(today.monthToDate))
        return [settled, deductionStat(settlement), monthToDate]
    }
}

extension RestPanel {
    init(today: Today, holidays: HolidayTable) {
        // 全天请假按休息日呈现，但标题为「今天请假」(AC-HOME-07)。
        let isLeave = today.leave?.period == .fullDay
        let monthDays = AttendanceRule(holidays: holidays).attendanceDayCount(in: today.date.yearMonth)
        self.init(
            headline: isLeave ? "今天请假" : "今天休息",
            tagline: isLeave ? nil : "不搬砖，不计钱。",
            nextAttendanceText: today.nextAttendanceDay.map { "下一个上班日 \(Format.date($0, relativeTo: today.date))" },
            stats: [
                StatItem(title: "本月已上班", value: "\(today.attendedDays)/\(monthDays) 天"),
                StatItem(title: "本月累计", value: Format.money(today.monthToDate)),
            ]
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
        // 半天假后那半天没有工时时没有任何一段，`barLength` 不会被用作除数。
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
        case .lunchBreak: "午休中"
        case .offWork: "已下班"
        }
    }
}

/// 当月应出勤日数为 0 (如全部被覆盖为不上班) 时的提示 (PRD 4.3.5 #19、AC-HOME-09)；否则为 nil。
private func noAttendanceNotice(_ today: LocalDate, holidays: HolidayTable) -> String? {
    AttendanceRule(holidays: holidays).attendanceDayCount(in: today.yearMonth) == 0 ? "本月没有要上班的日子" : nil
}
