import Foundation

/// 请掉的一段时间 [start, end)，落在当日计划上下班之内 (PRD 4.4.2)。上下班不跨零点，所以请假也不跨零点。
public struct LeaveRange: Sendable, Hashable {
    public let start: TimeOfDay
    public let end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    var span: MinuteSpan { MinuteSpan(start: start.minutesSinceMidnight, end: end.minutesSinceMidnight) }

    init(_ span: MinuteSpan) {
        self.init(start: TimeOfDay(minutesSinceMidnight: span.start), end: TimeOfDay(minutesSinceMidnight: span.end))
    }
}

/// 一条请假：请掉的时段 + 扣薪比例。同一天只有一条 (PRD 4.4.2 #4)。
/// 作为命令参数时未经校验，由 `apply` 用 `Validation.leave` 把关；从文件读入时校验比例与时段先后。
/// 比例编码为字符串，避免 JSON 数字经二进制浮点往返丢精度。
public struct Leave: Sendable, Equatable, Codable {
    /// 请掉的时段开始，计划上班至计划下班之间。
    public let start: TimeOfDay
    /// 请掉的时段结束 (不含)，晚于开始。
    public let end: TimeOfDay
    /// 扣薪比例，日薪的百分之几，0 至 100【D8】。请假扣薪 = 日薪 × 扣薪比例 ÷ 100。
    public let deductionPercent: Decimal

    public init(start: TimeOfDay, end: TimeOfDay, deductionPercent: Decimal) {
        self.start = start
        self.end = end
        self.deductionPercent = deductionPercent
    }

    public init(range: LeaveRange, deductionPercent: Decimal) {
        self.init(start: range.start, end: range.end, deductionPercent: deductionPercent)
    }

    public var range: LeaveRange { LeaveRange(start: start, end: end) }

    private enum CodingKeys: String, CodingKey { case start, end, deductionPercent, period }

    /// 只认时段写法；V1.8 之前的「全天 / 上午 / 下午」要靠当天的作息换算，见 `init(from:legacySchedule:)`。
    public init(from decoder: Decoder) throws {
        try self.init(from: decoder, legacySchedule: nil)
    }

    /// 读入一条请假。旧文件存的是时段名 (`period`)，按这天生效的作息 `legacySchedule` 换算成时段：
    /// 全天为计划上下班，上午、下午即快捷的前半天、后半天 (见 `LeaveQuickPick`)。没有作息时拒绝读入。
    init(from decoder: Decoder, legacySchedule: WorkSchedule?) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .deductionPercent)
        let percent = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        guard let percent, Validation.leaveDeductionPercent(percent) == nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .deductionPercent, in: container, debugDescription: "扣薪比例不在 0 至 100 之间：\(text)"
            )
        }
        if container.contains(.start) {
            let range = LeaveRange(
                start: try container.decode(TimeOfDay.self, forKey: .start),
                end: try container.decode(TimeOfDay.self, forKey: .end)
            )
            guard range.start < range.end else {
                throw DecodingError.dataCorruptedError(forKey: .end, in: container, debugDescription: "请假结束不晚于开始")
            }
            self.init(range: range, deductionPercent: percent)
            return
        }
        let period = try container.decode(LegacyLeavePeriod.self, forKey: .period)
        guard let legacySchedule else {
            throw DecodingError.dataCorruptedError(forKey: .period, in: container, debugDescription: "旧格式的请假缺少作息")
        }
        self.init(range: period.range(in: legacySchedule), deductionPercent: percent)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(NSDecimalNumber(decimal: deductionPercent).stringValue, forKey: .deductionPercent)
    }
}

/// V1.7 之前存下的请假时段名，只在读旧文件时用。
private enum LegacyLeavePeriod: String, Decodable {
    case fullDay, morning, afternoon

    /// 换算成时段：上午、下午即前半天、后半天。半天没有时长 (饭点紧贴计划上班或下班) 时取饭点那段，
    /// 请假后的当日计划与旧的半天假一致 (只剩另一半)；关闭饭点且计划只有 1 分钟这种极端情况取全天。
    func range(in schedule: WorkSchedule) -> LeaveRange {
        let pick: LeaveQuickPick = switch self {
        case .fullDay: .fullDay
        case .morning: .firstHalf
        case .afternoon: .secondHalf
        }
        let span = pick.span(in: schedule) ?? schedule.lunchSpan ?? schedule.span
        return LeaveRange(span)
    }
}
