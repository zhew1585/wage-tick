import Foundation

/// 工资怎么算 (issue #16，GLOSSARY)：按月填月薪，或按天填日薪。和金额一起按月记录 (`MonthlySalary`)，修改对当月整月生效。
/// - 按月：日薪 = 当月月薪 ÷ 当月应出勤日数 (ADR-0001)，满勤一个月正好等于月薪。
/// - 按天：日薪就是填的数，只有应出勤日有钱，周末与法定节假日都是 0；本月累计 = 日薪 × 实际上班天数。
public enum PayBasis: String, Sendable, Equatable, Codable, CaseIterable {
    case monthly
    case daily

    /// 输入框标签与切换上的字，如「月薪」「日薪」。
    public var label: String {
        switch self {
        case .monthly: "月薪"
        case .daily: "日薪"
        }
    }

    /// 输入框后面的单位，如「元/月」「元/日」。
    public var unit: String {
        switch self {
        case .monthly: "元/月"
        case .daily: "元/日"
        }
    }
}
