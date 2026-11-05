import Foundation

/// 目标 (PRD 4.5.1)：牛马录入的名称和金额，从激活那一刻起累计收入，达到即完成。
/// 金额、起算基准编码为字符串，避免 JSON 数字经二进制浮点往返丢精度。
public struct Goal: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    /// 1 至 20 字，已去掉首尾空白。
    public let name: String
    /// 大于 0。
    public let amount: Decimal
    public internal(set) var status: GoalStatus

    init(id: UUID = UUID(), name: String, amount: Decimal, status: GoalStatus) {
        self.id = id
        self.name = name
        self.amount = amount
        self.status = status
    }

    private enum CodingKeys: String, CodingKey { case id, name, amount, status, baseline, completedAt }

    /// 从文件读入时按新建同一套规则校验 (PRD 4.3.5 #9)，不合法抛解码错误。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decodeDecimal(forKey: .amount)
        if let error = Validation.goal(name: name, amount: amount) {
            throw DecodingError.dataCorruptedError(forKey: .name, in: container, debugDescription: error.message)
        }
        switch try container.decode(String.self, forKey: .status) {
        case "accumulating":
            status = .accumulating(baseline: try container.decodeDecimal(forKey: .baseline))
        case "completed":
            status = .completed(at: try container.decode(Date.self, forKey: .completedAt))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .status, in: container, debugDescription: "不认识的目标状态：\(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount.exactText, forKey: .amount)
        switch status {
        case .accumulating(let baseline):
            try container.encode("accumulating", forKey: .status)
            try container.encode(baseline.exactText, forKey: .baseline)
        case .completed(let completedAt):
            try container.encode("completed", forKey: .status)
            try container.encode(completedAt, forKey: .completedAt)
        }
    }
}

/// 目标状态 (PRD 4.5.2)。排队中留给目标队列 (#12)。
public enum GoalStatus: Sendable, Equatable {
    /// 累计中：起算基准 = 激活时的累计收入；累计额 = 累计收入 - 起算基准。
    case accumulating(baseline: Decimal)
    /// 已完成：记录完成时间并冻结，不受后续任何编辑影响。
    case completed(at: Date)
}

extension Decimal {
    /// 完整精度的十进制文本，如 `9142.857142857142857142857142857142857`。
    var exactText: String { NSDecimalNumber(decimal: self).stringValue }
}

private extension KeyedDecodingContainer {
    /// 读一个以字符串存放的十进制金额。
    func decodeDecimal(forKey key: Key) throws -> Decimal {
        let text = try decode(String.self, forKey: key)
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "不是金额：\(text)")
        }
        return value
    }
}
