import Foundation

/// 发薪日 (issue #20，GLOSSARY)：每月几号发工资，碰上不应出勤的日子怎么挪。
/// 全局一份，不按月记录；没设时 `Profile.payday` 为 nil，界面上不显示距发薪。
public struct Payday: Sendable, Equatable, Codable {
    /// 每月几号，1 至 31；当月没有这一天时 (如 11 月填 31) 按月末那天算。
    public let dayOfMonth: Int
    public let shift: PaydayShift

    /// 几号未经校验，由 `.setPayday` 命令拦下越界的值。
    public init(dayOfMonth: Int, shift: PaydayShift) {
        self.dayOfMonth = dayOfMonth
        self.shift = shift
    }

    private enum CodingKeys: String, CodingKey { case dayOfMonth, shift }

    /// 从文件读入时不信任内容：几号越界抛解码错误。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let day = try container.decode(Int.self, forKey: .dayOfMonth)
        guard Self.validDays.contains(day) else {
            throw DecodingError.dataCorruptedError(forKey: .dayOfMonth, in: container, debugDescription: "发薪日越界：\(day)")
        }
        self.init(dayOfMonth: day, shift: try container.decode(PaydayShift.self, forKey: .shift))
    }

    static let validDays = 1...31

    /// 设置页「发薪日」一行的值，如「每月 15 号 · 遇休息日提前」；不挪时只写几号。
    var summary: String {
        let base = "每月 \(dayOfMonth) 号"
        return switch shift {
        case .earlier: "\(base) · 遇休息日提前"
        case .later: "\(base) · 遇休息日顺延"
        case .unchanged: base
        }
    }
}

/// 发薪日碰上不应出勤的日子 (休息模式、法定节假日、单日覆盖) 时怎么挪。
public enum PaydayShift: String, Sendable, Equatable, Codable, CaseIterable {
    /// 提前到前一个应出勤日，默认。
    case earlier
    /// 顺延到下一个应出勤日。
    case later
    /// 不挪，照常那天发。
    case unchanged

    /// 发薪日表单三段切换上的文案。
    public var label: String {
        switch self {
        case .earlier: "提前到前一个上班日"
        case .later: "顺延"
        case .unchanged: "不变"
        }
    }
}
