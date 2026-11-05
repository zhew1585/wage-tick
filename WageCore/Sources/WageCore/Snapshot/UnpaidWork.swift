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
        let cutoff = now.unpaidWorkCutoff(on: now.localDate)
        let running = segments.last { $0.end == nil && now.date < cutoff }
        let total = segments.map { segment in
            let end = segment.end ?? min(now.date, cutoff)
            return max(0, Int((end.timeIntervalSince(segment.start) * 1000).rounded(.down)))
        }.reduce(0, +)
        let standard = Decimal(schedule.standardMilliseconds)
        milliseconds = total
        // 先乘后除，减少中间舍入。
        owed = dailyWage * Decimal(total) / standard
        perSecond = dailyWage * 1000 / standard
        runningSince = running?.start
        suspectedAllNighter = segments.contains { $0.suspectedAllNighter || ($0.end == nil && now.date >= cutoff) }
        hasRecords = !segments.isEmpty
        canStart = (status == .offWork || status == .restDay) && running == nil && now.date < cutoff
    }
}

extension WorkSchedule {
    /// 标准工时 (毫秒) = 计划下班 - 计划上班 - 午休时长 (PRD 4.2.3)，不受半天假影响。
    var standardMilliseconds: Int {
        let lunch = lunch.map { $0.end.minutesSinceMidnight - $0.start.minutesSinceMidnight } ?? 0
        return (end.minutesSinceMidnight - start.minutesSinceMidnight - lunch) * 60_000
    }
}
