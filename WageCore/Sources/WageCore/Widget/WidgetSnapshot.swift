import Foundation

/// 桌面小组件 (PRD F14) 某一刻要展示的内容。文字与数字都取自同一时刻的面板快照 (`TodayPanel`)，
/// 小组件和面板永远一致；外壳原样展示，只决定小号、中号、大号各摆哪几项。
public enum WidgetSnapshot: Sendable, Equatable {
    /// 未完成引导：提示打开 App 完成设置。
    case setup(WidgetSetup)
    /// 已完成引导：今天的情况。
    case today(WidgetToday)
}

/// 未完成引导时的提示。
public struct WidgetSetup: Sendable, Equatable {
    /// 如「先来设置一下」。
    public let headline: String
    /// 如「打开牛马鼓励器，填好月薪和作息」。
    public let message: String

    /// 小组件读不到数据 (App 还没打开过) 时也用它。
    public static let standard = WidgetSetup(headline: "先来设置一下", message: "打开牛马鼓励器，填好月薪和作息")
}

/// 已完成引导时小组件的内容。
public struct WidgetToday: Sendable, Equatable {
    /// 如「11月5日 周四」，同面板顶部日期。
    public let dateText: String
    /// 如「上班中」「白干中」，同面板顶部状态。
    public let statusLabel: String
    /// 状态的色调，外壳据此着色，与面板顶部状态一致。
    public let tone: WidgetTone
    public let main: WidgetMain
    /// 中号右栏的两项：上班的状态 (未上班、上班中、干饭中、请假中) 为距离下班、距离周末，其余为距离周末、本月累计。
    public let sideStats: [WidgetStat]
    /// 大号的统计行，同面板统计行；距离下班换成实时倒计时。
    public let stats: [WidgetStat]
    /// 累计中目标或空状态，同面板。
    public let goal: GoalCard
    /// 排队中目标，最多 2 个 (与累计中合计 3 个)，同面板攒钱队列。
    public let queued: [QueuedGoalCard]
    /// 小牛此刻的场景，同面板头图：决定大胆版小组件的底色与小牛姿势。
    public let scene: CowScene
    /// 每小时一格的进度格，同面板；休息日没在白干时为 nil。
    public let blocks: HourBlocks?
}

/// 状态色调，对应面板顶部状态的三种颜色：应出勤日 money、休息日 accent、白干中 loss。
public enum WidgetTone: Sendable, Equatable {
    case attendance
    case rest
    case unpaidWork
}

/// 主体：应出勤日与白干中是一个大数字，休息日 (含全天请假) 是小牛和下个上班日。
public enum WidgetMain: Sendable, Equatable {
    case amount(WidgetAmount)
    case rest(WidgetRest)
}

/// 大数字区。
public struct WidgetAmount: Sendable, Equatable {
    /// 如「今日已赚」「今日结算」「今日已倒贴」「昨天已倒贴」。
    public let label: String
    /// 固定 2 位小数，不带 ¥，如「571.43」(见 `Format.cents`)。¥ 由外壳单独排版。
    public let amount: String
    /// 大号主数字下方的小字，如「满勤日薪 ¥1000 · 时薪 ¥142.86」「准点下班，赢」「18:00 起 · 已白干」。
    public let caption: String
    /// 大号小字后面接的计时；只有白干中有 (已白干时长)。
    public let captionTimer: WidgetValue?
    /// 工作进度；应出勤日未下班时有，已下班与白干中为 nil。
    public let progress: WidgetProgress?
    /// 小号底部一行 (中号左栏没有进度条时也用它)：未下班为距离下班，白干中为「18:00 起」+ 已白干计时，
    /// 已下班为「准点下班，赢」或白干汇总 (没有值)。
    public let footer: WidgetStat
}

/// 休息日的主体。
public struct WidgetRest: Sendable, Equatable {
    /// 「今天休息」或「今天请假」(全天请假)。
    public let headline: String
    /// 如「下个上班日 11月9日 周一」；一年内都没有时为 nil。
    public let nextAttendanceText: String?
    /// 距下个上班日还有几天 (大胆版小组件的大数字)；一年内都没有时为 nil。
    public let daysUntilWork: Int?
}

/// 一项标题 + 值，如「距离下班 3:00:00」「本月累计 ¥3571.43」。
public struct WidgetStat: Sendable, Equatable {
    public let title: String
    /// 没有值时只显示标题 (如已下班的「准点下班，赢」)。
    public let value: WidgetValue?
    /// 醒目显示 (accent 色)：距离周末，同面板。
    public let isHighlighted: Bool

    public init(title: String, value: WidgetValue?, isHighlighted: Bool = false) {
        self.title = title
        self.value = value
        self.isHighlighted = isHighlighted
    }
}

/// 一项的值：固定文字，或由系统实时走的计时 (外壳用 SwiftUI 计时文字，不必每秒刷新小组件)。
public enum WidgetValue: Sendable, Equatable {
    case text(String)
    /// 倒计时到这一刻，h:mm:ss，到点停在 0:00:00。
    case countdown(to: Date)
    /// 从这一刻起正计时，h:mm:ss。白干中这一刻已扣掉开始那天之前几段的时长，计时即开始那天的白干总时长。
    case elapsed(since: Date)
}

/// 工作进度。
public struct WidgetProgress: Sendable, Equatable {
    /// 整体进度 0 至 1，小号、中号的单条进度条用。
    public let ratio: Double
    /// 如「57.14%」。
    public let percent: String
    /// 大号分段进度条，饭点与落在中间的请假是段与段之间的间隔，同面板。
    public let segments: [ProgressSegment]
    /// 中号进度条下方两端，如「10:00」「18:00」。
    public let startTime: String
    public let endTime: String
    /// 大号进度条下方两端，如「上班 10:00」「下班 18:00」，同面板。
    public let startText: String
    public let endText: String
}

extension WidgetSnapshot {
    /// 由同一时刻的快照推导。`now` 须与取快照的此刻相同。
    init(snapshot: Snapshot, now: Moment) {
        guard let panel = snapshot.panel, let today = snapshot.today else {
            self = .setup(.standard)
            return
        }
        self = .today(WidgetToday(panel: panel, today: today, now: now))
    }
}

extension WidgetToday {
    init(panel: TodayPanel, today: Today, now: Moment) {
        dateText = panel.dateText
        statusLabel = panel.statusLabel
        goal = panel.goal
        queued = panel.goalQueue?.upcoming ?? []
        scene = panel.cowScene
        blocks = panel.blocks
        switch panel.body {
        case .attendance(let attendance):
            tone = .attendance
            (main, stats, sideStats) = Self.attendance(attendance, today: today, now: now)
        case .rest(let rest):
            tone = .rest
            main = .rest(WidgetRest(
                headline: rest.headline,
                nextAttendanceText: today.nextAttendanceDay.map { "下个上班日 \(Format.date($0, relativeTo: today.date))" },
                daysUntilWork: today.nextAttendanceDay.map { $0.days(since: today.date) }
            ))
            stats = rest.stats.map(WidgetStat.init)
            // 统计行为 [本月已上班, 本月累计, 距离周末]，右栏先放距离周末。
            sideStats = stats.count == 3 ? [stats[2], stats[1]] : stats
        case .unpaidWork(let unpaidWork):
            tone = .unpaidWork
            (main, stats, sideStats) = Self.unpaidWork(unpaidWork, today: today, now: now)
        }
    }

    private typealias Parts = (main: WidgetMain, stats: [WidgetStat], sideStats: [WidgetStat])

    /// 应出勤日。面板统计行未下班为 [距离下班, 距离周末, 本月累计]，已下班为 [今日结算, 距离周末, 本月累计]。
    private static func attendance(_ panel: AttendancePanel, today: Today, now: Moment) -> Parts {
        let earned = today.earnings.map { Format.cents($0.earned) } ?? Format.cents(0)
        let stats = panel.stats.map(WidgetStat.init)
        guard let progress = panel.progress, let plan = today.plan else {
            // 已下班：主数字即今日结算，中号右栏不再重复它。
            let amount = WidgetAmount(
                label: "今日结算", amount: earned, caption: panel.caption, captionTimer: nil, progress: nil,
                footer: WidgetStat(title: panel.caption, value: nil)
            )
            return (.amount(amount), stats, Array(stats.dropFirst()))
        }
        // 未上班时还没开始倒计时，同面板显示「-」；上班中、干饭中、请假中倒计时到计划下班。
        let countdown = WidgetStat(
            title: "距离下班",
            value: today.status == .notStarted ? .text("-") : .countdown(to: plan.end)
        )
        let liveStats = [countdown] + stats.dropFirst()
        let amount = WidgetAmount(
            label: "今日已赚", amount: earned, caption: panel.caption, captionTimer: nil,
            progress: WidgetProgress(progress: progress, plan: plan, today: today, now: now), footer: countdown
        )
        return (.amount(amount), liveStats, Array(liveStats.prefix(2)))
    }

    /// 白干中 (含前一天开始、跨过零点还在计时)：主数字为开始那天已倒贴，计时为开始那天的白干总时长。
    private static func unpaidWork(_ panel: UnpaidWorkPanel, today: Today, now: Moment) -> Parts {
        let stats = panel.stats.map(WidgetStat.init)
        guard let running = today.unpaidWork.running else {
            // 面板是白干中时一定有计时中的那段，走不到这里。
            return (.amount(WidgetAmount(
                label: panel.label, amount: Format.cents(0), caption: panel.caption, captionTimer: nil, progress: nil,
                footer: WidgetStat(title: panel.caption, value: nil)
            )), stats, stats)
        }
        let start = Format.time(Moment(date: running.since, timeZone: now.timeZone))
        let day = running.date == today.date ? "" : "\(Format.shortDay(running.date, relativeTo: today.date)) "
        let since = "\(day)\(start) 起"
        let timer = WidgetValue.elapsed(since: now.date.addingTimeInterval(-Double(running.milliseconds) / 1000))
        let amount = WidgetAmount(
            label: panel.label, amount: Format.cents(running.owed), caption: "\(since) · 已白干", captionTimer: timer,
            progress: nil, footer: WidgetStat(title: since, value: timer)
        )
        // 统计行为 [今日结算, 距离周末, 本月累计]，主数字已是倒贴，右栏放后两项。
        return (.amount(amount), stats, Array(stats.dropFirst()))
    }
}

extension WidgetStat {
    /// 面板统计行的一项，值原样作为文字。
    init(_ item: StatItem) {
        self.init(title: item.title, value: .text(item.value), isHighlighted: item.isHighlighted)
    }
}

extension WidgetProgress {
    init(progress: WorkProgress, plan: DayPlan, today: Today, now: Moment) {
        ratio = today.earnings.map { NSDecimalNumber(decimal: $0.progress).doubleValue } ?? 0
        percent = progress.percent
        segments = progress.segments
        startTime = Format.time(Moment(date: plan.start, timeZone: now.timeZone))
        endTime = Format.time(Moment(date: plan.end, timeZone: now.timeZone))
        startText = progress.startText
        endText = progress.endText
    }
}
