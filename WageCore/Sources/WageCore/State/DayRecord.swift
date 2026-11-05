import Foundation

/// 日记录 (PRD 4.3.1)：一天一条，只保存牛马手动产生的内容。
/// 字段按 PRD 命名：单日覆盖、请假、扣钱记录、白干段，各由对应的票追加；本票只有请假。
/// 日薪、当日计划、状态、收入一律由规则推导，不存在这里。
public struct DayRecord: Sendable, Equatable, Codable {
    /// 请假 (PRD 4.4.2)；nil 表示这天没请假。同一天只有一条 (4.4.2 #4)。
    public internal(set) var leave: Leave?

    init(leave: Leave? = nil) {
        self.leave = leave
    }
}

/// 请假时段 (PRD 4.4.2)。
public enum LeavePeriod: String, Sendable, Equatable, Codable, CaseIterable {
    case fullDay    // 全天
    case morning    // 上午
    case afternoon  // 下午

    /// 切换时段时带出的扣薪比例 (%)：全天 100、半天 50【D4】，牛马可再修改。
    public var defaultDeductionPercent: Decimal {
        self == .fullDay ? 100 : 50
    }

    /// 上午、下午互为另一半；全天没有另一半。
    var otherHalf: LeavePeriod? {
        switch self {
        case .fullDay: nil
        case .morning: .afternoon
        case .afternoon: .morning
        }
    }
}

/// 一条请假：时段 + 扣薪比例。
/// 作为命令参数时未经校验，由 `apply` 用 `Validation.leaveDeductionPercent` 把关；从文件读入时同样校验。
/// 比例编码为字符串，避免 JSON 数字经二进制浮点往返丢精度。
public struct Leave: Sendable, Equatable, Codable {
    public let period: LeavePeriod
    /// 扣薪比例，日薪的百分之几，0 至 100【D8】。请假扣薪 = 日薪 × 扣薪比例 ÷ 100。
    public let deductionPercent: Decimal

    public init(period: LeavePeriod, deductionPercent: Decimal) {
        self.period = period
        self.deductionPercent = deductionPercent
    }

    private enum CodingKeys: String, CodingKey { case period, deductionPercent }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .deductionPercent)
        let percent = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        guard let percent, Validation.leaveDeductionPercent(percent) == nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .deductionPercent, in: container, debugDescription: "扣薪比例不在 0 至 100 之间：\(text)"
            )
        }
        self.init(period: try container.decode(LeavePeriod.self, forKey: .period), deductionPercent: percent)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(period, forKey: .period)
        try container.encode(NSDecimalNumber(decimal: deductionPercent).stringValue, forKey: .deductionPercent)
    }

    /// 同一天先后请上午假和下午假：合并为全天假，比例相加，最高 100% (PRD 4.3.5 #21)。
    /// 其余情况新的一条替换旧的 (4.4.2 #4)。
    func merged(into existing: Leave?) -> Leave {
        guard let existing, existing.period.otherHalf == period else { return self }
        return Leave(period: .fullDay, deductionPercent: min(100, existing.deductionPercent + deductionPercent))
    }
}
