import Foundation

/// 今天的白干情况 (PRD 4.4.3)。白干不改变日状态和任何收入 (PRD 4.3.3 不变量 2)。
public struct UnpaidWorkToday: Sendable, Equatable {
    /// 今日白干时长 (毫秒)：今天各段之和，计时中的那段算到此刻 (规则 2)。
    public let milliseconds: Int
    /// 今日已倒贴 = 白干时长 × 时薪，保留完整精度 (规则 4)。
    public let owed: Decimal
    /// 计时中今日已倒贴每秒的增量 = 时薪 ÷ 3600。
    public let perSecond: Decimal
    /// 计时中那段的开始时刻；没在计时为 nil。
    public let runningSince: Date?
    /// 今天有白干段在 23:59:59 被自动停止 (疑似通宵，PRD 4.3.5 #12)。
    public let suspectedAllNighter: Bool
    /// 今天有没有白干记录，决定已下班小字是「准点下班，赢」还是白干汇总 (规则 6)。
    public let hasRecords: Bool
    /// 此刻能否开始计时：已下班或休息日、没在计时、还没到 23:59:59 (规则 1、2、3)。
    public let canStart: Bool

    public var isRunning: Bool { runningSince != nil }
}

extension UnpaidWorkToday {
    /// `segments` 是今天的白干段。时薪按作息的标准工时计算，不受半天假影响 (规则 4)。
    /// 计时中且已过 23:59:59 的段 (还没推进到此刻) 按已在 23:59:59 自动停止推导，与 `advance` 的结果一致。
    init(segments: [UnpaidWorkSegment], status: DayStatus, dailyWage: Decimal, schedule: WorkSchedule, now: Moment) {
        let day = now.localDate
        let cutoff = now.unpaidWorkCutoff(on: day)
        let running = segments.last { $0.isRunning(on: day, now: now) }
        let total = segments.map { $0.milliseconds(on: day, now: now) }.reduce(0, +)
        milliseconds = total
        owed = schedule.owed(dailyWage: dailyWage, milliseconds: total)
        perSecond = schedule.owed(dailyWage: dailyWage, milliseconds: 1000)
        runningSince = running?.start
        suspectedAllNighter = segments.contains { $0.isSuspectedAllNighter(on: day, now: now) }
        hasRecords = !segments.isEmpty
        canStart = (status == .offWork || status == .restDay) && running == nil && now.date < cutoff
    }
}

extension UnpaidWorkSegment {
    /// 这段白干的时长 (毫秒)，`day` 是它所在的日子。计时中的那段算到此刻，最晚到当天 23:59:59，
    /// 与 `advance` 自动停止的结果一致 (规则 3)；结束早于开始的段按 0 计。
    func milliseconds(on day: LocalDate, now: Moment) -> Int {
        let end = end ?? min(now.date, now.unpaidWorkCutoff(on: day))
        return max(0, Int((end.timeIntervalSince(start) * 1000).rounded(.down)))
    }

    /// 此刻是否还在计时：没结束，且还没到当天 23:59:59。
    func isRunning(on day: LocalDate, now: Moment) -> Bool {
        end == nil && now.date < now.unpaidWorkCutoff(on: day)
    }

    /// 疑似通宵 (PRD 4.3.5 #12)：已在 23:59:59 被自动停止，或该停了还没推进。
    func isSuspectedAllNighter(on day: LocalDate, now: Moment) -> Bool {
        suspectedAllNighter || (end == nil && !isRunning(on: day, now: now))
    }
}

extension Moment {
    /// 白干自动停止时刻：`day` 当天 23:59:59 (PRD 参数表「白干自动停止时刻」)，按此刻所在时区。
    /// 计时中切换时区时按新时区推导、不追溯修正 (PRD 4.3.5 #11)：向东切可能让那段在开始时刻就结束，
    /// 向西切到前一天时今天的快照看不到那段计时 (此时开始会被拒绝)。都属罕见边界，接受。
    func unpaidWorkCutoff(on day: LocalDate) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 23, minute: 59, second: 59))!
    }
}

extension WorkSchedule {
    /// 倒贴 = 白干时长 × 时薪，时薪 = 日薪 ÷ 标准工时 (规则 4)，保留完整精度。先乘后除，减少中间舍入。
    func owed(dailyWage: Decimal, milliseconds: Int) -> Decimal {
        dailyWage * Decimal(milliseconds) / Decimal(standardMilliseconds)
    }

    /// 标准工时 (毫秒) = 计划下班 - 计划上班 - 午休时长 (PRD 4.2.3)，不受半天假影响。
    var standardMilliseconds: Int {
        let lunch = lunch.map { $0.end.minutesSinceMidnight - $0.start.minutesSinceMidnight } ?? 0
        return (end.minutesSinceMidnight - start.minutesSinceMidnight - lunch) * 60_000
    }
}
