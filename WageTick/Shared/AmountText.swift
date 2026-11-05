import Foundation

/// 目标金额输入框的文字。
enum AmountText {
    /// 只认纯数字写法，其他写法视为未填 (nil)；大于 0 等规则交给核心的 `Validation`。
    static func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) != nil else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}
