import Foundation

/// 录入校验规则 (PRD 4.3.5 #1 至 #3；扣钱 #5 见 `DeductionCommands.swift`)，`apply` 执行命令前用它们拦截，读回状态文件时也用它们把关。
/// 外壳的分步表单 (如引导第 1 步只填了月薪) 也直接调用，保证提示与命令一致。
public enum Validation {
    /// 月薪必须大于 0 (#1)，最多 2 位小数 (PRD 4.2.1)。
    /// PRD 只给了"非正数"的提示文案，小数位过多暂用同一条提示。
    public static func monthlySalary(_ amount: Decimal) -> CommandError? {
        guard amount > 0, hasAtMostTwoDecimals(amount) else { return .salaryNotPositive }
        return nil
    }

    /// 计划下班晚于计划上班 (#2)；饭点落在上下班之内、结束晚于开始，
    /// 且不能占满整个上下班时段，否则应有有效工时为 0 (#3)。
    public static func schedule(_ schedule: WorkSchedule) -> CommandError? {
        guard schedule.end > schedule.start else { return .endNotAfterStart }
        if let lunch = schedule.lunch {
            let inside = schedule.start <= lunch.start && lunch.end <= schedule.end
            let coversWholeDay = lunch.start == schedule.start && lunch.end == schedule.end
            guard lunch.end > lunch.start, inside, !coversWholeDay else { return .lunchOutsideWorkHours }
        }
        return nil
    }

    private static func hasAtMostTwoDecimals(_ amount: Decimal) -> Bool {
        var input = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return rounded == amount
    }
}
