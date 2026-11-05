import Foundation

/// 某个应出勤日的结算推导 (PRD 4.3.1 推导内容、4.3.4)。
/// 今日上限、结算、本月累计里每一天的数字都只从这里取，保证各处口径一致。
struct DaySettlement: Sendable, Equatable {
    /// 当日所在月的日薪。
    let dailyWage: Decimal
    /// 请假扣薪 = 日薪 × 扣薪比例 (PRD 4.4.2 #1)；没请假为 0。
    let leaveDeduction: Decimal

    /// `record` 为这天的日记录，没有记录时按满勤。
    init(dailyWage: Decimal, record: DayRecord?) {
        self.dailyWage = dailyWage
        leaveDeduction = record?.leave.map { dailyWage * $0.deductionPercent / 100 } ?? 0
    }

    /// 当日扣款 = 扣钱记录合计 + 请假扣薪 (GLOSSARY)。扣钱记录 (#7) 合并时加在这里。
    var deduction: Decimal { leaveDeduction }

    /// 今日上限 = 日薪 - 当日扣款，最低为 0【D1】。结算 = 今日上限。
    var cap: Decimal { max(0, dailyWage - deduction) }
}
