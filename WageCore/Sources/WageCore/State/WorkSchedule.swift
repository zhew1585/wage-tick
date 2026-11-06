import Foundation

/// 作息：计划上下班时间与饭点，对所有应出勤日相同 (PRD 4.2.3)。
public struct WorkSchedule: Sendable, Equatable, Codable {
    public let start: TimeOfDay
    public let end: TimeOfDay
    /// nil 表示关闭饭点，此时上下班之间全部计入有效工时。
    public let lunch: LunchBreak?

    public init(start: TimeOfDay, end: TimeOfDay, lunch: LunchBreak?) {
        self.start = start
        self.end = end
        self.lunch = lunch
    }

    /// 从文件读入时按引导同一套规则校验 (PRD 4.3.5 #2、#3)，不合法抛解码错误。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try container.decode(TimeOfDay.self, forKey: .start),
            end: try container.decode(TimeOfDay.self, forKey: .end),
            lunch: try container.decodeIfPresent(LunchBreak.self, forKey: .lunch)
        )
        if let error = Validation.schedule(self) {
            throw DecodingError.dataCorruptedError(forKey: .end, in: container, debugDescription: error.message)
        }
    }

    private enum CodingKeys: String, CodingKey { case start, end, lunch }

    /// 引导里的默认作息：09:00 至 18:00，饭点 12:00 至 13:00 (AC-ONB-01)。
    public static let `default` = WorkSchedule(
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 18, minute: 0),
        lunch: .default
    )
}

/// 饭点时段。
public struct LunchBreak: Sendable, Equatable, Codable {
    public let start: TimeOfDay
    public let end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    /// 默认饭点 12:00 至 13:00。
    public static let `default` = LunchBreak(
        start: TimeOfDay(hour: 12, minute: 0),
        end: TimeOfDay(hour: 13, minute: 0)
    )

    /// 饭点长度 (分钟)。
    public var minutes: Int { end.minutesSinceMidnight - start.minutesSinceMidnight }

    /// 改了上下班后自动带出的饭点：长 `length` 分钟，放在上下班的正中间，开始时刻对齐到 10 分钟，
    /// 两头至少各留 10 分钟上班。上下班之间放不下时为 nil。
    /// 如 09:00 至 18:00 为 13:00 至 14:00，16:00 至 23:00 为 19:00 至 20:00。
    public static func centered(between start: TimeOfDay, and end: TimeOfDay, length: Int = 60) -> LunchBreak? {
        let open = start.minutesSinceMidnight + Self.margin
        let close = end.minutesSinceMidnight - Self.margin
        guard length > 0, close - open >= length else { return nil }
        let middle = (start.minutesSinceMidnight + end.minutesSinceMidnight) / 2
        let snapped = Int((Double(middle - length / 2) / Double(Self.step)).rounded()) * Self.step
        let begin = min(max(snapped, open), close - length)
        return LunchBreak(start: TimeOfDay(minutesSinceMidnight: begin), end: TimeOfDay(minutesSinceMidnight: begin + length))
    }

    /// 自动带出的饭点两头至少留的上班时长 (分钟)。
    private static let margin = 10
    /// 自动带出的饭点开始时刻对齐的刻度 (分钟)。
    private static let step = 10
}

extension TimeOfDay {
    /// 当天 0 点起的第几分钟，0 至 1439。
    init(minutesSinceMidnight minutes: Int) {
        self.init(hour: minutes / 60, minute: minutes % 60)
    }
}
