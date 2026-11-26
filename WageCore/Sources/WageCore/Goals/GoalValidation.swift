import Foundation

extension Validation {
    /// 目标名称最多多少字 (PRD 4.7.2)。
    public static let goalNameLimit = 20

    /// 新建、编辑目标时金额最多多少 (含)。
    /// 金额太大时预计完成要往后数上万年，也放不进目标卡片；之前存下的超过上限的目标照常读入、显示，再次保存时才要求改小。
    public static let goalAmountLimit: Decimal = 999999

    /// 新建、编辑目标：名称 1 至 20 字 (去掉首尾空白后)，金额大于 0 (PRD 4.3.5 #9) 且不超过 `goalAmountLimit`。
    public static func goal(name: String, amount: Decimal) -> CommandError? {
        if let error = storedGoal(name: name, amount: amount) { return error }
        guard amount <= goalAmountLimit else { return .goalAmountTooLarge }
        return nil
    }

    /// 从文件读入的目标：名称 1 至 20 字 (去掉首尾空白后)，金额大于 0 (PRD 4.3.5 #9)；不查金额上限，免得丢掉之前存下的目标。
    static func storedGoal(name: String, amount: Decimal) -> CommandError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...goalNameLimit).contains(trimmed.count), amount > 0 else { return .invalidGoal }
        return nil
    }
}
