import Foundation

/// 今日概览面板应展示的全部文字 (PRD F4)，数字已按 D9 格式化好，外壳原样展示，不做任何计算或拼接。
public struct TodayPanel: Sendable, Equatable {
    /// 顶部日期，如「2月11日 周三」。
    public let dateText: String
    /// 顶部时间，如「15:07」。
    public let timeText: String
    /// 顶部状态标签，如「上班中」。
    public let statusLabel: String
    public let body: Body
    /// 面板顶部的提示条，按顺序展示，没有时为空，如节假日数据缺失 (AC-HOME-08)。
    public let notices: [String]
    /// 「今天扣钱了」入口 (F5)；休息日为 nil，不显示按钮 (AC-FINE-07)。
    public let deductionEntry: DeductionEntry?

    public enum Body: Sendable, Equatable {
        /// 应出勤日：未上班、上班中、午休中、已下班。
        case attendance(AttendancePanel)
        /// 休息日。
        case rest(RestPanel)
    }
}

/// 休息日的面板内容 (PRD F4)。
public struct RestPanel: Sendable, Equatable {
    /// 如「今天休息」。
    public let headline: String
    public let stats: [StatItem]

    public init(headline: String, stats: [StatItem]) {
        self.headline = headline
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
    /// 主数字下方一行小字，如「今日上限 ¥1000 · 每秒 +0.0397」。
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
    /// 如「已工作 4 / 7 小时」。
    public let label: String
    /// 如「57.14%」。
    public let percent: String
    /// 进度条各段，午休显示为段与段之间的间隔。
    public let segments: [ProgressSegment]
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
    init(today: Today, now: Moment, holidays: HolidayTable) {
        dateText = Format.date(today.date, relativeTo: today.date)
        timeText = Format.time(now)
        statusLabel = today.status.label
        notices = [holidays.missingNotice(on: today.date)].compactMap { $0 }
        deductionEntry = today.settlement.map(DeductionEntry.init(settlement:))
        guard let earnings = today.earnings, let plan = today.plan, let settlement = today.settlement else {
            body = .rest(RestPanel(today: today))
            return
        }
        body = .attendance(AttendancePanel(today: today, earnings: earnings, settlement: settlement, plan: plan, now: now.date))
    }
}

extension AttendancePanel {
    init(today: Today, earnings: Earnings, settlement: DaySettlement, plan: DayPlan, now: Date) {
        let monthToDate = StatItem(title: "本月累计", value: Format.money(today.monthToDate))
        // 已下班时今日已赚 = 今日上限 = 今日结算 (PRD 4.3.4)。
        headline = Format.rollingMoney(earnings.earned)
        if today.status == .offWork {
            // 白干记录留给后续票，本期已下班一律是准点下班。
            caption = "准点下班，赢"
            progress = nil
            let settled = StatItem(title: "今日结算", value: Format.money(earnings.cap))
            stats = [settled, Self.deductionStat(settlement), monthToDate].compactMap { $0 }
        } else {
            caption = "今日上限 \(Format.money(earnings.cap)) · 每秒 +\(Format.trimmed(earnings.perSecond))"
            progress = WorkProgress(plan: plan, progress: earnings.progress, now: now)
            stats = [StatItem(title: "距离下班", value: Format.countdown(from: now, to: plan.end)), monthToDate]
        }
        deductions = settlement.deductions.map(DeductionItem.init)
        notice = Self.notice(settlement)
    }
}

extension RestPanel {
    init(today: Today) {
        let next = today.nextAttendanceDay.map {
            StatItem(title: "下一个应出勤日", value: Format.date($0, relativeTo: today.date))
        }
        self.init(headline: "今天休息", stats: [
            StatItem(title: "本月已上班", value: "\(today.attendedDays) 天"),
            StatItem(title: "本月累计", value: Format.money(today.monthToDate)),
        ] + [next].compactMap { $0 })
    }
}

extension WorkProgress {
    init(plan: DayPlan, progress: Decimal, now: Date) {
        let elapsed = Format.trimmed(Format.hours(milliseconds: plan.elapsedMilliseconds(at: now)))
        let total = Format.trimmed(Format.hours(milliseconds: plan.effectiveMilliseconds))
        label = "已工作 \(elapsed) / \(total) 小时"
        percent = Format.percent(progress)
        let barLength = plan.workPeriods.map(\.length).reduce(0, +)
        segments = plan.workPeriods.map { period in
            let walked = min(max(now.timeIntervalSince(period.start), 0), period.length)
            return ProgressSegment(share: period.length / barLength, filled: walked / period.length)
        }
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
