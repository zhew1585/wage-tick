import Foundation

extension Validation {
    /// 目标名称最多多少字 (PRD 4.7.2)。
    static let goalNameLimit = 20

    /// 目标名称 1 至 20 字 (去掉首尾空白后)，金额大于 0 (PRD 4.3.5 #9)。
    public static func goal(name: String, amount: Decimal) -> CommandError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...goalNameLimit).contains(trimmed.count), amount > 0 else { return .invalidGoal }
        return nil
    }
}
