import Foundation

/// 配置校验规则 (PRD 4.3.5 #1 至 #3)，`apply` 执行命令前用它们拦截。
/// 外壳的分步表单 (如引导第 1 步只填了月薪) 也直接调用，保证提示与命令一致。
public enum Validation {
    /// 月薪必须大于 0 (#1)。
    public static func monthlySalary(_ amount: Decimal) -> CommandError? {
        amount > 0 ? nil : .salaryNotPositive
    }

    /// 计划下班晚于计划上班 (#2)，午休落在上下班之内且结束晚于开始 (#3)。
    public static func schedule(_ schedule: WorkSchedule) -> CommandError? {
        guard schedule.end > schedule.start else { return .endNotAfterStart }
        if let lunch = schedule.lunch {
            let inside = schedule.start <= lunch.start && lunch.end <= schedule.end
            guard lunch.end > lunch.start, inside else { return .lunchOutsideWorkHours }
        }
        return nil
    }
}
