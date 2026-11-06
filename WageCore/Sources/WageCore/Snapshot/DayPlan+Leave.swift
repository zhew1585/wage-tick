import Foundation

/// 一天里的一段时刻 [start, end)，按当天 0 点起的分钟数。请假与当日计划都按它推导，再落到绝对时刻上。
struct MinuteSpan: Sendable, Equatable {
    let start: Int
    let end: Int

    var length: Int { end - start }

    /// 与 `other` 重叠的分钟数。
    func overlap(_ other: MinuteSpan) -> Int {
        max(0, min(end, other.end) - max(start, other.start))
    }

    /// 截到 `bounds` 之内的部分；没有重叠时为 nil。
    func clipped(to bounds: MinuteSpan) -> MinuteSpan? {
        let span = MinuteSpan(start: max(start, bounds.start), end: min(end, bounds.end))
        return span.length > 0 ? span : nil
    }

    func contains(_ minute: Int) -> Bool { start <= minute && minute < end }
}

/// 请假表单的快捷时段 (PRD F6)：全天、前半天、后半天。
/// 前半天、后半天以饭点为分界：前半天从计划上班到饭点开始，后半天从饭点结束到计划下班；
/// 关闭饭点时以计划上下班中点 (向下取整到分) 为分界 (4.3.5 #20)。
public enum LeaveQuickPick: Sendable, Equatable, CaseIterable {
    case fullDay
    case firstHalf
    case secondHalf

    public var label: String {
        switch self {
        case .fullDay: "全天"
        case .firstHalf: "前半天"
        case .secondHalf: "后半天"
        }
    }

    /// 这个快捷时段在 `schedule` 下请掉的那段；没有时长 (饭点紧贴计划上班或下班) 时为 nil。
    func span(in schedule: WorkSchedule) -> MinuteSpan? {
        let day = schedule.span
        let boundary = schedule.halfDayBoundary
        let span = switch self {
        case .fullDay: day
        case .firstHalf: MinuteSpan(start: day.start, end: boundary.start)
        case .secondHalf: MinuteSpan(start: boundary.end, end: day.end)
        }
        return span.length > 0 ? span : nil
    }
}

extension WorkSchedule {
    /// 计划上下班 [计划上班, 计划下班)。
    var span: MinuteSpan { MinuteSpan(start: start.minutesSinceMidnight, end: end.minutesSinceMidnight) }

    var lunchSpan: MinuteSpan? {
        lunch.map { MinuteSpan(start: $0.start.minutesSinceMidnight, end: $0.end.minutesSinceMidnight) }
    }

    /// 前半天、后半天的分界：有饭点时为饭点，关闭饭点时为计划上下班的中点 (长度为 0，向下取整到分)。
    var halfDayBoundary: MinuteSpan {
        let midpoint = (span.start + span.end) / 2
        return lunchSpan ?? MinuteSpan(start: midpoint, end: midpoint)
    }

    /// 标准工时 (分钟) = 计划下班 - 计划上班 - 饭点时长 (PRD 4.2.3)。
    var standardMinutes: Int { span.length - (lunchSpan?.length ?? 0) }

    /// 请假时段 `range` 请掉的有效工时 (分钟)：截到计划上下班之内，扣掉其中的饭点。
    func leaveWorkMinutes(_ range: LeaveRange) -> Int {
        guard let leave = range.span.clipped(to: span) else { return 0 }
        return leave.length - (lunchSpan?.overlap(leave) ?? 0)
    }

    /// 请 `range` 这段假时带出的扣薪比例 (%)：请掉的有效工时 ÷ 标准工时 × 100，四舍五入到 2 位【D4】；
    /// 请掉全部工时即全天，为 100。牛马可再修改。
    public func defaultLeavePercent(_ range: LeaveRange) -> Decimal {
        guard leavePlan(range) != nil else { return 100 }
        let ratio = Decimal(leaveWorkMinutes(range)) * 100 / Decimal(standardMinutes)
        return min(100, Format.round(ratio, scale: 2))
    }

    /// 请 `range` 这段假后的当日计划 (按分钟，PRD 4.3.2)；请掉了全部工时 (含只剩饭点) 即全天请假，为 nil。
    /// 计划上班挪到开头连着的请假、饭点之后，计划下班挪到结尾连着的请假、饭点之前：
    /// 如请前半天 (到饭点开始) 后从饭点结束开始上班，不再经过干饭中 (4.3.3)。
    /// 落在中间的请假把一天分成前后两段上班；与计划上下班不相交的请假 (如改了作息) 不影响计划。
    func leavePlan(_ range: LeaveRange) -> LeavePlan? {
        guard let leave = range.span.clipped(to: span) else {
            return LeavePlan(start: span.start, end: span.end, lunch: lunchSpan, leave: nil)
        }
        let gaps = [leave, lunchSpan].compactMap { $0 }
        var start = span.start
        var end = span.end
        // 请假与饭点可能首尾相接，各推一遍不够，推两遍。
        for _ in 0..<2 {
            for gap in gaps where gap.contains(start) { start = gap.end }
            for gap in gaps where gap.start < end && end <= gap.end { end = gap.start }
        }
        guard start < end else { return nil }
        let bounds = MinuteSpan(start: start, end: end)
        return LeavePlan(start: start, end: end, lunch: lunchSpan?.clipped(to: bounds), leave: leave.clipped(to: bounds))
    }
}

/// 请假调整后的当日计划，按分钟。`lunch`、`leave` 都已截到计划上下班之内，没有交集时为 nil。
struct LeavePlan: Sendable, Equatable {
    let start: Int
    let end: Int
    let lunch: MinuteSpan?
    /// 落在中间的请假；开头、结尾的请假已经挪走了计划上下班，这里为 nil。
    let leave: MinuteSpan?

    /// 「今天上班」的各段：只按请假切开，饭点不切，如「10:00–14:00、16:00–18:00」。
    var stretches: [MinuteSpan] {
        guard let leave else { return [MinuteSpan(start: start, end: end)] }
        return [MinuteSpan(start: start, end: leave.start), MinuteSpan(start: leave.end, end: end)].filter { $0.length > 0 }
    }
}

extension DayPlan {
    /// 当日计划 (PRD 4.3.2)：作息经请假调整后的结果 (见 `WorkSchedule.leavePlan`)；全天请假没有计划，返回 nil。
    init?(schedule: WorkSchedule, leave: LeaveRange?, on day: LocalDate, now: Moment) {
        guard let leave else {
            self.init(schedule: schedule, on: day, now: now)
            return
        }
        guard let plan = schedule.leavePlan(leave) else { return nil }
        let date = { (minute: Int) in now.date(on: day, at: TimeOfDay(minutesSinceMidnight: minute)) }
        let period = { (span: MinuteSpan) in Period(start: date(span.start), end: date(span.end)) }
        self.init(start: date(plan.start), end: date(plan.end), lunch: plan.lunch.map(period), leave: plan.leave.map(period))
    }
}
