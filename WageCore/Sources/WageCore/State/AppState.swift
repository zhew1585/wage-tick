import Foundation

/// 核心计算的状态：只保存牛马手动产生的内容与配置，推导内容一律不存 (PRD 4.3.1)。
/// 由外壳持久化到本机 (ADR-0002)，通过 `apply` 演进，通过 `snapshot` 读出。
public struct AppState: Sendable, Equatable, Codable {
    /// 引导完成后才有；nil 即"未完成引导"。
    public internal(set) var profile: Profile?

    public init() {
        profile = nil
    }
}

/// 完成引导后的牛马配置。
public struct Profile: Sendable, Equatable, Codable {
    /// 安装日期，即完成引导那天；历史从这个月开始 (PRD 4.1.1)。
    public let installDate: LocalDate
    /// 按月份记录的月薪，按月份升序。未来月份沿用最近一次设置 (PRD 4.2.1)。
    public internal(set) var salaries: [MonthlySalary]
    public internal(set) var schedule: WorkSchedule
    public internal(set) var launchAtLogin: Bool

    /// 某月适用的月薪：该月及之前最近一次设置的月薪。
    /// 系统时间被拨回到安装月之前时 (PRD 4.3.5 #11)，退回最早一条。
    func salary(for month: YearMonth) -> Decimal {
        let entry = salaries.last { $0.month <= month } ?? salaries[0]
        return entry.amount
    }
}

/// 某个月的月薪。
/// 金额编码为字符串，避免 JSON 数字经二进制浮点往返丢精度。
public struct MonthlySalary: Sendable, Equatable, Codable {
    public let month: YearMonth
    public let amount: Decimal

    private enum CodingKeys: String, CodingKey { case month, amount }

    init(month: YearMonth, amount: Decimal) {
        self.month = month
        self.amount = amount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        month = try container.decode(YearMonth.self, forKey: .month)
        let text = try container.decode(String.self, forKey: .amount)
        guard let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container, debugDescription: "月薪不是合法数字：\(text)")
        }
        self.amount = amount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(month, forKey: .month)
        try container.encode(NSDecimalNumber(decimal: amount).stringValue, forKey: .amount)
    }
}
