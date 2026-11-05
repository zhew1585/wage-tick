import Foundation

/// 某个应出勤日的结算推导 (PRD 4.3.1 推导内容、4.3.4)。
/// 当日扣款、今日上限、结算只从这里取：今天的今日上限、本月累计里已过各日的结算都用它算。
struct DaySettlement: Sendable, Equatable {
    /// 当月日薪，保留完整精度。
    let dailyWage: Decimal
    /// 当天各笔扣钱记录折算成的金额，与日记录里的先后一致。
    let deductions: [ChargedDeduction]
    /// 请假扣薪 = 日薪 × 扣薪比例 (PRD 4.4.2 #1)；没请假为 0。
    let leaveDeduction: Decimal

    /// 当日扣款 = 扣钱记录合计 + 请假扣薪 (GLOSSARY)。
    var deductionTotal: Decimal {
        deductions.map(\.money).reduce(0, +) + leaveDeduction
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
        leaveDeduction = record?.leave.map { dailyWage * $0.deductionPercent / 100 } ?? 0
    }
}

extension DaySettlement {
    /// 当月日薪 (PRD 4.2.4)，今天、目标累计收入与历史共用 `AttendanceRule.dailyWage(in:profile:)` 这一个公式。
    static func dailyWage(profile: Profile, month: YearMonth, rule: AttendanceRule) -> Decimal {
        rule.dailyWage(in: month, profile: profile)
    }
}

/// 一笔扣钱记录，连同按当月日薪折算出的金额。
struct ChargedDeduction: Sendable, Equatable {
    let deduction: Deduction
    let money: Decimal
}
