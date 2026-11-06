import Foundation

/// 节假日表的存储格式，App 交给桌面小组件 (PRD F14) 时用：只存数据源给的节假日与缺失年份。
/// 单日覆盖与休息模式来自状态，取快照时再并入 (见 `overlaying(_:)`)，这里不存。
extension HolidayTable: Codable {
    private enum CodingKeys: String, CodingKey {
        case days
        case missingYears
    }

    /// 一天的类型，按日期排好存成数组，文件稳定、好读。
    private struct Day: Codable {
        let date: LocalDate
        let kind: HolidayKind
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let days = try container.decode([Day].self, forKey: .days)
        self.init(
            days: Dictionary(days.map { ($0.date, $0.kind) }, uniquingKeysWith: { _, last in last }),
            missingYears: try container.decode(Set<Int>.self, forKey: .missingYears)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(days.sorted { $0.key < $1.key }.map { Day(date: $0.key, kind: $0.value) }, forKey: .days)
        try container.encode(missingYears.sorted(), forKey: .missingYears)
    }
}

/// 存成「holiday」「makeupDay」。
extension HolidayKind: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "holiday": self = .holiday
        case "makeupDay": self = .makeupDay
        default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "不认识的节假日类型 \(raw)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self == .holiday ? "holiday" : "makeupDay")
    }
}
