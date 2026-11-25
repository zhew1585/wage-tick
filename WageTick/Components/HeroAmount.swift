import Foundation
import SwiftUI

/// 头图大数字，经典版的样子 (同 nightly.20261112.15 面板的主数字)：JetBrains Mono，墨色，整数 54/700，¥ 与小数位 26/600，排成一行。
/// 文字原样取自快照 (如「¥571.4286」「¥1,000」「2」)，这里只拆开排版；没有小数时只有整数。
/// `paused` 时 (干饭、请假、已下班) 小数位变灰，表示钱暂时不涨。`unit` 接在后面 (如「天」「小时」)。
/// `size` 仍按大胆版的字号传 (默认 96)，这里按 54 ÷ 96 折成经典版字号，调用方不用改。
///
/// 用法：`HeroAmount(text: panel.headline, theme: theme, paused: isLunch)`
struct HeroAmount: View {
    let text: String
    let theme: HeroTheme
    var paused = false
    var unit: String?
    /// 整数部分的字号 (大胆版口径)，位数多时由视图自己缩小。
    var size: CGFloat = 96
    /// 数字最宽多少 (给右下角小牛留位置)。
    var maxWidth: CGFloat = 220

    /// 大胆版字号折成经典版：96 对应经典版主数字的 54。
    private static let scale: CGFloat = 54.0 / 96.0
    /// ¥、小数位、单位相对整数的字号比 (经典版 26 ÷ 54)。
    private static let affixRatio: CGFloat = 26.0 / 54.0

    var body: some View {
        let parts = Self.split(text)
        let big = size * Self.scale
        let small = big * Self.affixRatio
        let ink = theme.classic.number
        HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
            number(parts, big: big, small: small, ink: ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let unit {
                Text(unit).font(AppFont.ui(small, .semibold)).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text + (unit ?? ""))
    }

    /// ¥、整数、小数位拼成一段文字，放不下时一起缩小。
    private func number(_ parts: (currency: String?, integer: String, decimals: String), big: CGFloat, small: CGFloat, ink: Color) -> Text {
        let affix = AppFont.num(small, .semibold)
        var result = Text(Self.grouped(parts.integer)).font(AppFont.num(big, .bold)).tracking(-1.5).foregroundStyle(ink)
        if let currency = parts.currency {
            result = Text(currency).font(affix).foregroundStyle(ink) + result
        }
        if !parts.decimals.isEmpty {
            result = result + Text("." + parts.decimals).font(affix).foregroundStyle(paused ? Palette.muted : ink)
        }
        return result
    }

    /// 整数部分加千分位 (设计稿「¥1,000」)；已经带逗号或不是纯数字 (如倒计时「0:45」) 时原样。
    nonisolated static func grouped(_ integer: String) -> String {
        guard integer.count > 3, integer.allSatisfy(\.isNumber) else { return integer }
        var result = ""
        for (index, character) in integer.enumerated() {
            if index > 0, (integer.count - index) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return result
    }

    /// 「¥571.4286」拆成 ¥、571、4286；「−¥50」拆成 −¥、50、空。
    nonisolated static func split(_ text: String) -> (currency: String?, integer: String, decimals: String) {
        var rest = Substring(text)
        var currency: String?
        if let yen = rest.firstIndex(of: "¥"), rest[..<yen].allSatisfy({ !$0.isNumber }) {
            currency = String(rest[...yen])
            rest = rest[rest.index(after: yen)...]
        }
        guard let dot = rest.firstIndex(of: ".") else { return (currency, String(rest), "") }
        return (currency, String(rest[..<dot]), String(rest[rest.index(after: dot)...]))
    }
}

/// 金额显示带千分位：把快照给的「¥3492.86」整数部分加上逗号，变成「¥3,492.86」；不是金额时原样。
/// `groupedAll` 把一句话里所有「¥数字」都加上千分位，如「共 ¥4298 · 搬砖 4.3 天」→「共 ¥4,298 · 搬砖 4.3 天」。
enum BoldNumber {
    nonisolated static func groupedAll(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "¥(\\d{4,})") else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            result.replaceSubrange(range, with: HeroAmount.grouped(String(result[range])))
        }
        return result
    }

    nonisolated static func grouped(_ text: String) -> String {
        let parts = HeroAmount.split(text)
        let integer = HeroAmount.grouped(parts.integer)
        return (parts.currency ?? "") + integer + (parts.decimals.isEmpty ? "" : "." + parts.decimals)
    }
}
