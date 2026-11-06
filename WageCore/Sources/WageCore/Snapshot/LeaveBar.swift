import Foundation

/// 请假表单的「请哪段」时间条 (设计稿 F6 · 时间条)：整条是这天的计划上下班，饭点画成一块深色。
/// 位置一律用 0 至 1 的比例 (计划上班为 0，计划下班为 1)，外壳只把比例乘上宽度。
/// 拖动、吸附与快捷时段都在这里算，保证拖出来的时段总能通过 `Validation.leaveRange`。
public struct LeaveBar: Sendable, Equatable {
    /// 这天生效的作息，未经请假调整。
    let schedule: WorkSchedule
    /// 饭点在时间条上的位置；关闭饭点时为 nil。
    public let lunch: Segment?
    /// 刻度：每 10 分钟一根，整点的更高。
    public let ticks: [Tick]
    /// 刻度下的时刻文字：两端必有，中间按跨度挑几个整点，保证互不重叠。
    public let labels: [Label]
    /// 快捷时段：全天、前半天、后半天；没有时长或不合规的不给 (如饭点紧贴计划上班时没有前半天)。
    public let quickPicks: [QuickPick]

    /// 时间条上的一段，`start`、`end` 为比例。
    public struct Segment: Sendable, Equatable {
        public let start: Double
        public let end: Double
    }

    public struct Tick: Sendable, Equatable {
        public let position: Double
        /// 整点。
        public let isHour: Bool
    }

    public struct Label: Sendable, Equatable {
        public let position: Double
        /// 如「14:00」。
        public let text: String
    }

    public struct QuickPick: Sendable, Equatable {
        /// 如「前半天」。
        public let title: String
        public let range: LeaveRange
    }

    /// 时间条上方右侧的时段说明：时段如「14:00 – 16:00」，时长 (请掉的有效工时，不含饭点) 如「2 小时」。
    public struct Title: Sendable, Equatable {
        public let range: String
        public let duration: String
    }

    /// 拖的是哪个把手。
    public enum Handle: Sendable {
        case start
        case end
    }
}

extension LeaveBar {
    /// 中间的时刻文字离两端、彼此至少隔开整条的这个比例 (320 宽时约 48pt)，免得「12:00」这样的文字挤在一起。
    private static let labelSpacing = 0.15
    /// 中间时刻文字的间隔 (小时) 候选：从小到大取第一个让整条最多分成 4 格的。
    private static let labelIntervals = [1, 2, 3, 4, 6, 12]

    init(schedule: WorkSchedule) {
        self.schedule = schedule
        let day = schedule.span
        let position = { (minute: Int) in Double(minute - day.start) / Double(day.length) }
        lunch = schedule.lunchSpan.map { Segment(start: position($0.start), end: position($0.end)) }
        let step = Validation.leaveStepMinutes
        let firstTick = (day.start + step - 1) / step * step
        ticks = stride(from: firstTick, through: day.end, by: step).map { Tick(position: position($0), isHour: $0 % 60 == 0) }
        let interval = (Self.labelIntervals.first { day.length <= $0 * 60 * 4 } ?? 24) * 60
        let middle = stride(from: (day.start / interval + 1) * interval, to: day.end, by: interval).filter {
            min(position($0), 1 - position($0)) >= Self.labelSpacing
        }
        labels = ([day.start] + middle + [day.end]).map {
            Label(position: position($0), text: Format.time(TimeOfDay(minutesSinceMidnight: $0)))
        }
        quickPicks = LeaveQuickPick.allCases.compactMap { pick in
            guard let span = pick.span(in: schedule), Validation.leaveRange(LeaveRange(span), schedule: schedule) == nil else {
                return nil
            }
            return QuickPick(title: pick.label, range: LeaveRange(span))
        }
    }

    /// 全天：新请假时预选的时段。
    public var fullDay: LeaveRange { LeaveRange(schedule.span) }

    /// 某个时刻在时间条上的比例，计划上下班之外的截到两端。
    public func position(of time: TimeOfDay) -> Double {
        let day = schedule.span
        return min(1, max(0, Double(time.minutesSinceMidnight - day.start) / Double(day.length)))
    }

    /// 时段说明，如「14:00 – 16:00」「2 小时」。
    public func title(of range: LeaveRange) -> Title {
        Title(
            range: "\(Format.time(range.start)) – \(Format.time(range.end))",
            duration: Format.leaveDuration(minutes: schedule.leaveWorkMinutes(range))
        )
    }

    /// 时段变了时带出的扣薪比例 (%)，见 `WorkSchedule.defaultLeavePercent`。
    public func defaultPercent(for range: LeaveRange) -> Decimal {
        schedule.defaultLeavePercent(range)
    }

    /// 把 `handle` 拖到比例 `position` 处：吸附到最近的刻度 (或计划上下班、饭点边界)，
    /// 不越过另一个把手，至少留出最短时长 (`Validation.leaveMinimumMinutes`)。
    public func dragging(_ handle: Handle, of range: LeaveRange, to position: Double) -> LeaveRange {
        let span = range.span
        let target = minute(at: position)
        let gap = minimumLength
        switch handle {
        case .start:
            guard let start = nearest(to: target, in: snapPoints.filter { $0 <= span.end - gap }) else { return range }
            return LeaveRange(MinuteSpan(start: start, end: span.end))
        case .end:
            guard let end = nearest(to: target, in: snapPoints.filter { $0 >= span.start + gap }) else { return range }
            return LeaveRange(MinuteSpan(start: span.start, end: end))
        }
    }

    /// 整段平移比例 `offset` (拖选中的那段)：不出计划上下班，两端各自吸附，长度尽量不变。
    public func moving(_ range: LeaveRange, by offset: Double) -> LeaveRange {
        let day = schedule.span
        let span = range.span
        let shift = offset * Double(day.length)
        let clampedStart = min(max(Double(span.start) + shift, Double(day.start)), Double(day.end - span.length))
        guard let start = nearest(to: clampedStart, in: snapPoints.filter { $0 <= day.end - span.length }) else { return range }
        let end = snapPoints.contains(start + span.length)
            ? start + span.length
            : nearest(to: Double(start + span.length), in: snapPoints.filter { $0 >= start + minimumLength })
        guard let end else { return range }
        return LeaveRange(MinuteSpan(start: start, end: end))
    }

    /// 请假最短时长 (分钟)：计划本身更短时为整个计划。
    private var minimumLength: Int {
        min(Validation.leaveMinimumMinutes, schedule.span.length)
    }

    /// 可以吸附的时刻 (分钟)，升序：计划上下班之内每 10 分钟一个，加上计划上下班与饭点边界 (或中点)。
    private var snapPoints: [Int] {
        let day = schedule.span
        let step = Validation.leaveStepMinutes
        let grid = stride(from: (day.start + step - 1) / step * step, through: day.end, by: step)
        return Set(grid).union(schedule.leaveAnchors).sorted()
    }

    private func minute(at position: Double) -> Double {
        let day = schedule.span
        return Double(day.start) + min(1, max(0, position)) * Double(day.length)
    }

    private func nearest(to target: Double, in points: [Int]) -> Int? {
        points.min { abs(Double($0) - target) < abs(Double($1) - target) }
    }
}
