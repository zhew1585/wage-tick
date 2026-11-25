import SwiftUI

/// 头图里大号金额输入的统一规格 (同引导第 1 步)：数字 JetBrains Mono 54/700 (同头图主数字)、前缀 (¥、−¥) 26，字号固定，输入过程中不缩放；
/// 位数由各处限制 (`limited`)，最长时刚好放在小牛左边。用在引导工资、扣钱金额、新目标金额。
enum HeroNumberInput {
    /// 数字字号。JetBrains Mono 等宽，54 号每位约 32 宽，六位约 195。
    static let size: CGFloat = 54
    /// 前缀 (¥、−¥、−) 与后缀 (%) 的字号。
    static let affixSize: CGFloat = 26
    /// 输入框上面多留的高度：光标按整行高画，比数字字面高出一截，不留的话光标会贴到标题。
    static let caretClearance: CGFloat = 8

    /// 只留数字与一个小数点：整数加小数最多 `maxDigits` 位，小数最多 `maxDecimals` 位 (0 时不收小数点)。
    /// 多打的字直接吞掉，粘贴进来的非数字字符也去掉。
    nonisolated static func limited(_ text: String, maxDigits: Int, maxDecimals: Int = 0) -> String {
        var result = ""
        var digits = 0
        var decimals: Int?
        for character in text {
            if character == ".", maxDecimals > 0, decimals == nil, digits < maxDigits {
                decimals = 0
                result.append(character)
            } else if character.isWholeNumber, digits < maxDigits, (decimals ?? 0) < maxDecimals || decimals == nil {
                digits += 1
                if let count = decimals { decimals = count + 1 }
                result.append(character)
            }
        }
        return result
    }
}

extension View {
    /// 头图大号输入：`text` 变了就按位数限制过滤一遍。
    func heroNumberLimit(_ text: Binding<String>, maxDigits: Int, maxDecimals: Int = 0) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            let limited = HeroNumberInput.limited(newValue, maxDigits: maxDigits, maxDecimals: maxDecimals)
            if limited != newValue { text.wrappedValue = limited }
        }
    }
}
