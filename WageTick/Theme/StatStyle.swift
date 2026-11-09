import SwiftUI

/// 统计项的值怎么显示，面板统计行与桌面小组件共用 (小组件扩展也编译这个文件)。
/// 扣款 (以「−」开头) 用 loss 色；醒目项 (距离周末) 用 accent 色；其余 ink。
/// 数字用等宽字体；「明天休息」「正在休息」这类纯文字用界面字体加粗，字号小 2 号，与数字视觉上一样大。
enum StatStyle {
    static func color(_ value: String, isHighlighted: Bool) -> Color {
        if value.hasPrefix("−") { return Palette.loss }
        return isHighlighted ? Palette.accent : Palette.ink
    }

    static func font(_ value: String, numSize: CGFloat) -> Font {
        value.contains(where: \.isNumber) ? AppFont.num(numSize, .semibold) : AppFont.ui(numSize - 2, .bold)
    }
}
