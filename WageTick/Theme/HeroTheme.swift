import SwiftUI
import WageCore

/// 大胆版头图的配色 (设计稿「首页 · 大胆版」与「大胆风格」三张画板)：每个状态一种主色，渐变从右上到左下加深。
/// 上班中橙、未上班天蓝、已下班紫、白干中黑红、休息日黄、发薪日 (赶上休息日) 与已到手绿、扣钱红、历史墨色。
/// 头图里的文字、翻牌数字、气泡强调色都跟着主色走，视图只取这里的颜色。
///
/// 用法：`BoldHero(theme: .orange, …)`；首页按状态取 `HeroTheme.forPanel(_:)`。
struct HeroTheme: Equatable {
    /// 渐变的浅色端 (右上) 与深色端 (左下)。
    let top: Color
    let bottom: Color
    /// 头图标题 (站酷体) 与 ¥ 符号。
    let kicker: Color
    /// 大数字。
    let number: Color
    /// 日期、说明行等次要文字。
    let secondary: Color
    /// 返回胶囊的底色 (半透明)。
    let chip: Color
    /// 返回胶囊上的文字与箭头。
    let onChip: Color
    /// 小数位翻牌的底色与字色。
    let tile: Color
    let tileText: Color
    /// 翻牌最后一位的高亮底色与字色。
    let tileHighlight: Color
    let tileHighlightText: Color
    /// 气泡里大字的颜色。
    let bubbleAccent: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topTrailing, endPoint: .bottomLeading)
    }
}

extension HeroTheme {
    /// 上班中、干饭中、请假中、新目标、目标与设置页。
    static let orange = HeroTheme(
        top: Color(hex: 0xFF7A2E), bottom: Color(hex: 0xF24E0A),
        kicker: Palette.ink, number: .white, secondary: .white.opacity(0.8),
        chip: .white.opacity(0.2), onChip: .white,
        tile: Palette.ink, tileText: .white, tileHighlight: Palette.highlight, tileHighlightText: Palette.ink,
        bubbleAccent: Palette.accent
    )

    /// 未上班。
    static let sky = HeroTheme(
        top: Color(hex: 0x5CC8FF), bottom: Color(hex: 0x1E88E5),
        kicker: Palette.ink, number: .white, secondary: .white.opacity(0.85),
        chip: .white.opacity(0.22), onChip: .white,
        tile: Palette.ink, tileText: .white, tileHighlight: Palette.highlight, tileHighlightText: Palette.ink,
        bubbleAccent: Color(hex: 0x1E88E5)
    )

    /// 已下班。
    static let violet = HeroTheme(
        top: Color(hex: 0x6B5CE7), bottom: Color(hex: 0x3A2E9E),
        kicker: Palette.highlight, number: .white, secondary: .white.opacity(0.75),
        chip: .white.opacity(0.18), onChip: .white,
        tile: .white.opacity(0.15), tileText: .white, tileHighlight: .white.opacity(0.15), tileHighlightText: .white,
        bubbleAccent: Color(hex: 0x3A2E9E)
    )

    /// 白干中 (含休息日被迫营业)。
    static let night = HeroTheme(
        top: Color(hex: 0x3A2E28), bottom: Color(hex: 0x140F0C),
        kicker: Palette.hot, number: .white, secondary: .white.opacity(0.6),
        chip: .white.opacity(0.15), onChip: .white,
        tile: .white.opacity(0.12), tileText: .white, tileHighlight: Palette.hot, tileHighlightText: .white,
        bubbleAccent: Palette.hot
    )

    /// 休息日、请假表单。
    static let sun = HeroTheme(
        top: Color(hex: 0xFFE869), bottom: Color(hex: 0xFFC414),
        kicker: Palette.ink, number: Palette.ink, secondary: Palette.ink.opacity(0.7),
        chip: Palette.ink.opacity(0.1), onChip: Palette.ink,
        tile: Palette.ink, tileText: .white, tileHighlight: .white, tileHighlightText: Palette.ink,
        bubbleAccent: Color(hex: 0xB07800)
    )

    /// 发薪日赶上休息日、已到手、更新已准备好。
    static let mint = HeroTheme(
        top: Color(hex: 0x37C25A), bottom: Color(hex: 0x168A34),
        kicker: Palette.highlight, number: .white, secondary: .white.opacity(0.8),
        chip: .white.opacity(0.2), onChip: .white,
        tile: Palette.ink, tileText: .white, tileHighlight: Palette.highlight, tileHighlightText: Palette.ink,
        bubbleAccent: Color(hex: 0x168A34)
    )

    /// 今天扣钱了。
    static let red = HeroTheme(
        top: Color(hex: 0xFF6A4D), bottom: Color(hex: 0xD9300F),
        kicker: Palette.ink, number: .white, secondary: .white.opacity(0.8),
        chip: .white.opacity(0.2), onChip: .white,
        tile: Palette.ink, tileText: .white, tileHighlight: Palette.highlight, tileHighlightText: Palette.ink,
        bubbleAccent: Color(hex: 0xD9300F)
    )

    /// 历史 (账本)。
    static let ledger = HeroTheme(
        top: Color(hex: 0x3A332D), bottom: Color(hex: 0x15110E),
        kicker: Palette.highlight, number: .white, secondary: .white.opacity(0.7),
        chip: .white.opacity(0.15), onChip: .white,
        tile: .white.opacity(0.12), tileText: .white, tileHighlight: Palette.highlight, tileHighlightText: Palette.ink,
        bubbleAccent: Palette.ink
    )

    /// 首页按小牛场景取主色：白干中黑红，未上班天蓝，已下班紫，休息日黄 (发薪日赶上休息日整页变绿)，其余 (上班中、干饭、请假、发薪临近、上班日发薪) 橙。
    static func forPanel(_ panel: TodayPanel) -> HeroTheme {
        if case .unpaidWork = panel.body { return .night }
        if case .rest = panel.body { return panel.cowScene == .payday ? .mint : .sun }
        return switch panel.cowScene {
        case .beforeWork: .sky
        case .offWork: .violet
        default: .orange
        }
    }
}

extension HeroTheme {
    /// 桌面小组件按小牛场景取主色，同首页 (`forPanel`)。
    static func forWidget(_ today: WidgetToday) -> HeroTheme {
        switch today.tone {
        case .unpaidWork: return .night
        case .rest: return today.scene == .payday ? .mint : .sun
        case .attendance:
            return switch today.scene {
            case .beforeWork: .sky
            case .offWork: .violet
            default: .orange
            }
        }
    }
}
