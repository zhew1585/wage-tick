import Foundation

/// 某个应出勤日的结算推导 (PRD 4.3.1 推导内容、4.3.4)。
/// 当日扣款、今日上限、结算只从这里取：今天的今日上限、本月累计里已过各日的结算都用它算。
/// 请假扣薪 (#8) 也应并入 `deductionTotal`。
struct DaySettlement: Sendable, Equatable {
    /// 当月日薪，保留完整精度。
    let dailyWage: Decimal
    /// 当天各笔扣钱记录折算成的金额，与日记录里的先后一致。
    let deductions: [ChargedDeduction]

    /// 当日扣款 = 扣钱记录合计 (+ 请假扣薪，#8)。
    var deductionTotal: Decimal {
        deductions.map(\.money).reduce(0, +)
    }

    /// 今日上限 = 日薪 - 当日扣款，最低为 0【D1】；当天结束后即为结算。
    var cap: Decimal {
        max(0, dailyWage - deductionTotal)
    }

    /// 当日扣款超过日薪 (PRD 4.3.5 #6)：今天已经白干了。
    var isOverDeducted: Bool {
        deductionTotal > dailyWage
    }

    /// 没有日记录的应出勤日 (含安装前已过的日子) 结算 = 日薪 (PRD 4.1.1、4.3.4)。
    init(dailyWage: Decimal, record: DayRecord?) {
        self.dailyWage = dailyWage
        deductions = (record?.deductions ?? []).map {
            ChargedDeduction(deduction: $0, money: $0.amount.money(dailyWage: dailyWage))
        }
    }
}

/// 一笔扣钱记录，连同按当月日薪折算出的金额。
struct ChargedDeduction: Sendable, Equatable {
    let deduction: Deduction
    let money: Decimal
}
