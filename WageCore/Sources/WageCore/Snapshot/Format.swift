import Foundation

/// 金额展示格式 (PRD 4.7.1 第 5 条，D9)。计算全程保留完整精度，只在这里取舍。
enum Format {
    /// 滚动区域 (菜单栏数字、面板主数字)：四舍五入到 4 位，永远显示 4 位小数，不带货币符号。
    static func rolling(_ amount: Decimal) -> String {
        let text = NSDecimalNumber(decimal: round(amount, scale: 4)).stringValue
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return "\(parts[0]).\(fraction.padding(toLength: 4, withPad: "0", startingAt: 0))"
    }

    /// 四舍五入 (half up) 到 `scale` 位小数。
    static func round(_ amount: Decimal, scale: Int) -> Decimal {
        var input = amount
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
