import SwiftUI

/// App 窗口里的头图用经典配色 (2026-11-25 起，同 nightly.20261112.15 的界面)：米白平底、墨色字，不再按状态铺渐变色。
/// 页面照旧传 `HeroTheme.orange`、`.sun` 这些状态主题 (桌面小组件仍按它们上色)，
/// 头图、大数字、气泡这些共享组件画之前先取 `classic`，状态只留下一个强调色 `tone`。
/// 只编进 App，不进小组件扩展。
///
/// 用法：`let style = theme.classic`，之后只用 `style` 里的颜色。
extension HeroTheme {
    /// 状态强调色：白干与扣钱 loss，休息日 accent，账本 (历史) ink，其余 (上班、目标、设置、发薪) money。
    /// 用在状态圆点与文字、气泡里的大字。
    var tone: Color {
        switch self {
        case .night, .red: Palette.loss
        case .sun: Palette.accent
        case .ledger: Palette.ink
        default: Palette.money
        }
    }

    /// 经典配色：底 bg，标题与数字 ink，次要文字 muted，返回按钮无底色，强调色取 `tone`。
    var classic: HeroTheme {
        HeroTheme(
            top: Palette.bg, bottom: Palette.bg,
            kicker: Palette.ink, number: Palette.ink, secondary: Palette.muted,
            chip: Palette.surface, onChip: Palette.ink,
            tile: Palette.surface, tileText: Palette.ink, tileHighlight: Palette.accentSoft, tileHighlightText: Palette.accent,
            bubbleAccent: tone
        )
    }
}
