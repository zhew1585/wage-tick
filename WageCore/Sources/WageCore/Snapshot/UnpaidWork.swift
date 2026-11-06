import Foundation

/// 今天的白干情况 (PRD 4.4.3)。白干不改变日状态和任何收入 (PRD 4.3.3 不变量 2)。
public struct UnpaidWorkToday: Sendable, Equatable {
    /// 今日白干时长 (毫秒)：今天开始的各段之和，计时中的那段算到此刻 (规则 2)。前一天开始、跨过零点的段算在前一天。
    public let milliseconds: Int
    /// 今日已倒贴 = 白干时长 × 时薪，保留完整精度 (规则 4)。
    public let owed: Decimal
    /// 计时中今日已倒贴每秒的增量 = 时薪 ÷ 3600。
    public let perSecond: Decimal
    /// 计时中的那段，可能是前一天 (或更早) 开始、跨过了零点的 (规则 3)；没在计时为 nil。
    public let running: RunningUnpaidWork?
    /// 今天开始的段里有被自动停止的 (可能忘了停，PRD 4.3.5 #12)。
    public let autoStopped: Bool
    /// 今天有没有白干记录，决定已下班小字是「准点下班，赢」还是白干汇总 (规则 6)。
    public let hasRecords: Bool
    /// 此刻能否开始计时：已下班或休息日，且没在计时 (规则 1、2)。
    public let canStart: Bool

    public var isRunning: Bool { running != nil }
    /// 计时中那段的开始时刻；没在计时为 nil。
    public var runningSince: Date? { running?.since }
}

/// 计时中的那段白干，连同它所在那天 (开始那天) 的合计。跨过零点后仍按开始那天算 (规则 3)。
public struct RunningUnpaidWork: Sendable, Equatable {
    /// 开始那天，即这段记在哪天的日记录里。
    public let date: LocalDate
    /// 这段的开始时刻。
    public let since: Date
    /// 开始那天的白干时长 (毫秒)：那天各段之和，这段算到此刻。
    public let milliseconds: Int
    /// 开始那天已倒贴，保留完整精度。
    public let owed: Decimal
}

extension UnpaidWorkToday {
    /// 计时中且已过自动停止时刻的段 (还没推进到此刻) 按已自动停止推导，与 `advance` 的结果一致。
    init(dayRecords: [DayRecord], status: DayStatus, clock: UnpaidWorkClock) {
        let day = clock.now.localDate
        let segments = dayRecords.first { $0.date == day }?.unpaidWork ?? []
        let total = clock.milliseconds(segments, on: day)
        let running = RunningUnpaidWork(dayRecords: dayRecords, clock: clock)
        milliseconds = total
        owed = clock.owed(on: day, milliseconds: total)
        perSecond = clock.owed(on: day, milliseconds: 1000)
        self.running = running
        autoStopped = segments.contains { clock.isAutoStopped($0, on: day) }
        hasRecords = !segments.isEmpty
        canStart = (status == .offWork || status == .restDay) && running == nil
    }
}

extension RunningUnpaidWork {
    /// 找出计时中的那段 (同一时间最多一段)；没有时为 nil。只有没结束的段才需要推导自动停止时刻。
    init?(dayRecords: [DayRecord], clock: UnpaidWorkClock) {
        for record in dayRecords {
            guard let segment = record.unpaidWork.last(where: { clock.isRunning($0, on: record.date) }) else { continue }
            let total = clock.milliseconds(record.unpaidWork, on: record.date)
            self.init(date: record.date, since: segment.start, milliseconds: total, owed: clock.owed(on: record.date, milliseconds: total))
            return
        }
        return nil
    }
}

extension WorkSchedule {
    /// 倒贴 = 白干时长 × 时薪，时薪 = 日薪 ÷ 标准工时 (规则 4)，保留完整精度。先乘后除，减少中间舍入。
    func owed(dailyWage: Decimal, milliseconds: Int) -> Decimal {
        dailyWage * Decimal(milliseconds) / Decimal(standardMilliseconds)
    }

    /// 标准工时 (毫秒) = 计划下班 - 计划上班 - 饭点时长 (PRD 4.2.3)，不受请假影响。
    var standardMilliseconds: Int {
        let lunch = lunch.map { $0.end.minutesSinceMidnight - $0.start.minutesSinceMidnight } ?? 0
        return (end.minutesSinceMidnight - start.minutesSinceMidnight - lunch) * 60_000
    }
}
