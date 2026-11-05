import Foundation

/// 月薪输入框的文字。
enum SalaryText {
    /// 只认纯数字写法，其他写法视为未填 (nil)；正数、小数位等规则交给核心的 `Validation`。
    static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) != nil else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}
