import Foundation

/// 作息：计划上下班时间与午休，对所有应出勤日相同 (PRD 4.2.3)。
public struct WorkSchedule: Sendable, Equatable, Codable {
    public let start: TimeOfDay
    public let end: TimeOfDay
    /// nil 表示关闭午休，此时上下班之间全部计入有效工时。
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

    /// 引导里的默认作息：09:00 至 18:00，午休 12:00 至 13:00 (AC-ONB-01)。
    public static let `default` = WorkSchedule(
        start: TimeOfDay(hour: 9, minute: 0),
        end: TimeOfDay(hour: 18, minute: 0),
        lunch: .default
    )
}

/// 午休时段。
public struct LunchBreak: Sendable, Equatable, Codable {
    public let start: TimeOfDay
    public let end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    /// 默认午休 12:00 至 13:00。
    public static let `default` = LunchBreak(
        start: TimeOfDay(hour: 12, minute: 0),
        end: TimeOfDay(hour: 13, minute: 0)
    )
}
