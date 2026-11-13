import Foundation
import SwiftUI

/// 头图大数字 (设计稿「数字当主角」)：小号 ¥ + Archivo Black 大整数，小数位排成一格一格的翻牌，最后一位高亮，暗示它一直在跳。
/// 文字原样取自快照 (如「¥571.4286」「¥1,000」「2」)，这里只拆开排版；没有小数时只有整数。
/// `paused` 时 (干饭、请假) 翻牌变灰，表示钱暂时不涨。`unit` 接在整数后面 (如「天」「小时」)，用站酷体。
///
/// 用法：`HeroAmount(text: panel.headline, theme: theme, paused: isLunch)`
struct HeroAmount: View {
    let text: String
    let theme: HeroTheme
    var paused = false
    var unit: String?
    /// 整数部分的字号，位数多时由视图自己缩小。
    var size: CGFloat = 96
    /// 整数部分最宽多少 (给右下角小牛留位置)。
    var maxWidth: CGFloat = 220

    var body: some View {
        let parts = Self.split(text)
        VStack(alignment: .leading, spacing: Spacing.s6) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.s2) {
                if let currency = parts.currency {
                    Text(currency).font(AppFont.heavy(size * 0.34)).foregroundStyle(theme.kicker)
                }
                Text(Self.grouped(parts.integer))
                    .font(AppFont.heavy(size))
                    .tracking(-size * 0.04)
                    .foregroundStyle(theme.number)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                if let unit {
                    Text(unit).font(AppFont.fun(size * 0.36)).foregroundStyle(theme.kicker)
                }
            }
            .frame(maxWidth: maxWidth, alignment: .leading)
            if !parts.decimals.isEmpty {
                DecimalTiles(digits: parts.decimals, theme: theme, paused: paused)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text + (unit ?? ""))
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

/// 小数位翻牌：一个小圆点，后面每位一格 30×42，最后一位用高亮色。
private struct DecimalTiles: View {
    let digits: String
    let theme: HeroTheme
    let paused: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(".").font(AppFont.heavy(26)).foregroundStyle(theme.kicker).frame(width: 12)
            ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
                let last = index == digits.count - 1 && !paused
                Text(String(digit))
                    .font(AppFont.heavy(24))
                    .foregroundStyle(last ? theme.tileHighlightText : theme.tileText)
                    .frame(width: 30, height: 42)
                    .background(
                        paused ? Color.white.opacity(0.2) : (last ? theme.tileHighlight : theme.tile),
                        in: RoundedRectangle(cornerRadius: Radius.r8)
                    )
            }
        }
    }
}

/// 大胆版里的金额显示 (设计稿带千分位)：把快照给的「¥3492.86」整数部分加上逗号，变成「¥3,492.86」；不是金额时原样。
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
