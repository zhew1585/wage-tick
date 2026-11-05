import Foundation

/// 「今天扣钱了」入口 (PRD F5)：只在应出勤日出现，休息日没有 (AC-FINE-07)。
/// 扣钱表单的实时预览用它对比：当前快照的入口是起点，草稿试算 (`apply` 后再 `snapshot`) 的入口是终点。
public struct DeductionEntry: Sendable, Equatable {
    /// 今日上限，如「¥950」。
    public let capText: String
    /// 当日扣款超过日薪时的提示 (PRD 4.3.5 #6)，否则为 nil。
    public let warning: String?
    /// 预览里收入项的标题：今天为「今日上限」，历史补记过去的日子为「结算」(#15)。
    public let capTitle: String

    /// 预览文案「今日上限 ¥x → ¥y」；草稿试算失败 (如金额还没填) 时只显示起点「今日上限 ¥x」。
    public func previewLine(to draft: DeductionEntry?) -> String {
        guard let draft else { return "\(capTitle) \(capText)" }
        return "\(capTitle) \(capText) → \(draft.capText)"
    }
}

/// 面板里的一笔扣钱明细 (AC-FINE-04)。
public struct DeductionItem: Sendable, Equatable, Identifiable {
    /// 编辑、删除命令用的标识。
    public let id: Int
    /// 原因标签，如「迟到」；没选原因时为「扣钱」。
    public let title: String
    /// 折算后的金额，如「−¥50」。
    public let amount: String
    /// 说明：按百分比时带「日薪 10%」，再接备注；都没有时为 nil。
    public let detail: String?
    /// 录入时的内容，编辑表单据此回填。
    public let input: DeductionInput
}

/// 当日扣款超过日薪时的提示文案 (PRD 4.3.5 #6)。
private let overDeductedWarning = "今天已经白干了，再扣就倒贴了"

extension DeductionEntry {
    init(settlement: DaySettlement, capTitle: String = "今日上限") {
        capText = Format.money(settlement.cap)
        warning = AttendancePanel.notice(settlement)
        self.capTitle = capTitle
    }
}

extension DeductionItem {
    init(_ charged: ChargedDeduction) {
        let deduction = charged.deduction
        let ratio: String? = switch deduction.amount {
        case .fixed: nil
        case .percentOfDailyWage(let percent): "日薪 \(Format.trimmed(percent))%"
        }
        let note = deduction.note.isEmpty ? nil : deduction.note
        let parts = [ratio, note].compactMap { $0 }
        id = deduction.id
        title = deduction.reason?.label ?? "扣钱"
        amount = Format.deduction(charged.money)
        detail = parts.isEmpty ? nil : parts.joined(separator: " · ")
        input = deduction.input
    }
}

extension AttendancePanel {
    /// 统计行里的「扣款 −¥50」；没有扣款时不出现。
    static func deductionStat(_ settlement: DaySettlement) -> StatItem? {
        guard settlement.deductionTotal > 0 else { return nil }
        return StatItem(title: "扣款", value: Format.deduction(settlement.deductionTotal))
    }

    /// 当日扣款超过日薪时面板上的提示。
    static func notice(_ settlement: DaySettlement) -> String? {
        settlement.isOverDeducted ? overDeductedWarning : nil
    }
}

extension Format {
    /// 扣款金额：带负号 (U+2212) 与 ¥，按 `trimmed` 取舍，如「−¥50」。
    static func deduction(_ amount: Decimal) -> String {
        "−¥" + trimmed(amount)
    }
}
