import Foundation

/// 日记录 (PRD 4.3.1)：某一天牛马手动产生的内容。
/// 字段按 PRD 命名：单日覆盖、请假、扣钱记录、白干段；目前有扣钱记录 (#7) 与请假 (#8)，其余由各自的票追加。
/// 日薪、今日上限、结算等推导内容一律不存，见 `DaySettlement`。
public struct DayRecord: Sendable, Equatable, Codable {
    public let date: LocalDate
    /// 扣钱记录 (PRD 4.4.1)，1:N，按记录先后排列。
    public internal(set) var deductions: [Deduction]
    /// 请假 (PRD 4.4.2)；nil 表示这天没请假。同一天只有一条 (4.4.2 #4)。
    public internal(set) var leave: Leave?

    private enum CodingKeys: String, CodingKey { case date, deductions, leave }

    init(date: LocalDate, deductions: [Deduction] = [], leave: Leave? = nil) {
        self.date = date
        self.deductions = deductions
        self.leave = leave
    }

    /// 其他票追加的字段可能让一条日记录没有扣钱记录，缺省视为空。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(LocalDate.self, forKey: .date)
        deductions = try container.decodeIfPresent([Deduction].self, forKey: .deductions) ?? []
        leave = try container.decodeIfPresent(Leave.self, forKey: .leave)
    }

    /// 没有任何牛马录入的内容时，这条日记录可以删掉。
    var isEmpty: Bool { deductions.isEmpty && leave == nil }
}

/// 扣钱记录 (PRD 4.4.1)：牛马自己记下的一笔某天被扣的钱。
public struct Deduction: Sendable, Equatable, Codable, Identifiable {
    /// 编辑、删除时用来指认这一笔，在整个状态里唯一。
    public let id: Int
    public let amount: DeductionAmount
    /// 原因标签，可不选，只用于展示。
    public let reason: DeductionReason?
    /// 备注，最多 50 字，可为空。
    public let note: String

    private enum CodingKeys: String, CodingKey { case id, amount, reason, note }

    init(id: Int, input: DeductionInput) {
        self.id = id
        amount = input.amount
        reason = input.reason
        note = input.note
    }

    /// 从文件读入时按录入同一套规则校验 (PRD 4.3.5 #5)，不合法抛解码错误。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let input = DeductionInput(
            amount: try container.decode(DeductionAmount.self, forKey: .amount),
            reason: try container.decodeIfPresent(DeductionReason.self, forKey: .reason),
            note: try container.decode(String.self, forKey: .note)
        )
        if let error = Validation.deduction(input) {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container, debugDescription: error.message)
        }
        self.init(id: try container.decode(Int.self, forKey: .id), input: input)
    }

    /// 录入时的内容，编辑表单据此回填。
    public var input: DeductionInput {
        DeductionInput(amount: amount, reason: reason, note: note)
    }
}

/// 记账方式与数值 (PRD 4.4.1)。
/// 数值编码为字符串，避免 JSON 数字经二进制浮点往返丢精度。
public enum DeductionAmount: Sendable, Equatable, Codable {
    /// 按金额，单位元。
    case fixed(Decimal)
    /// 按日薪百分比，如 10 表示日薪的 10%；日薪变化时金额随之重算。
    case percentOfDailyWage(Decimal)

    /// 记账方式之外的那个数值 (元或 %)。
    public var value: Decimal {
        switch self {
        case .fixed(let value), .percentOfDailyWage(let value): value
        }
    }

    /// 折算成某天的扣款金额，保留完整精度。
    func money(dailyWage: Decimal) -> Decimal {
        switch self {
        case .fixed(let value): value
        case .percentOfDailyWage(let percent): dailyWage * percent / 100
        }
    }

    private enum CodingKeys: String, CodingKey { case method, value }
    private enum Method: String, Codable { case fixed, percentOfDailyWage }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .value)
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "扣钱数值不是数字：\(text)")
        }
        switch try container.decode(Method.self, forKey: .method) {
        case .fixed: self = .fixed(value)
        case .percentOfDailyWage: self = .percentOfDailyWage(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let method: Method = switch self {
        case .fixed: .fixed
        case .percentOfDailyWage: .percentOfDailyWage
        }
        try container.encode(method, forKey: .method)
        try container.encode(NSDecimalNumber(decimal: value).stringValue, forKey: .value)
    }
}

/// 扣钱原因标签 (PRD 4.4.1)，只用于展示。
public enum DeductionReason: String, Sendable, Equatable, Codable, CaseIterable {
    case late, leftEarly, other

    /// 展示文案。
    public var label: String {
        switch self {
        case .late: "迟到"
        case .leftEarly: "早退"
        case .other: "其他"
        }
    }
}

extension AppState {
    /// 某天的日记录；没有录入过任何内容时为 nil。
    func dayRecord(on date: LocalDate) -> DayRecord? {
        dayRecords.first { $0.date == date }
    }
}
