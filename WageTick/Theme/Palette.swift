import SwiftUI

/// 设计稿的颜色 token (Pencil 变量)，视图里只用这里的颜色，不写死色值。
/// 设计稿只有浅色一套，App 窗口统一用浅色外观 (见 `AppDelegate`)；菜单栏小牛是模板图，跟随菜单栏深浅。
enum Palette {
    /// 窗口、面板底色。
    static let bg = Color(hex: 0xFFFDF8)
    /// 次级底色：卡片、次要按钮、分组背景。
    static let surface = Color(hex: 0xF5F0E6)
    /// 分隔线、输入框描边。
    static let line = Color(hex: 0xE7DFD1)
    /// 主文字、主按钮底色。
    static let ink = Color(hex: 0x1F1B16)
    /// 次要文字、标签、说明。
    static let muted = Color(hex: 0x8A8073)
    /// 强调色：休息日、请假、提醒。
    static let accent = Color(hex: 0xE8590C)
    static let accentSoft = Color(hex: 0xFDEBDD)
    /// 赚钱：上班中、满勤、开关打开。
    static let money = Color(hex: 0x2B8A3E)
    static let moneySoft = Color(hex: 0xE3F4E6)
    /// 亏钱：扣钱、白干、错误提示。
    static let loss = Color(hex: 0xD9480F)
    static let lossSoft = Color(hex: 0xFBE4DA)
    /// 被扣钱的小圆点与图例色块 (设计稿 P5 月日历直接写的 #FF8A5B)：落在 lossSoft 底和 ink 底 (今天) 上都看得清。
    static let lossDot = Color(hex: 0xFF8A5B)
    /// 纯白：输入框、日历格子、开关圆钮 (设计稿里直接写的 #FFFFFF)。
    static let card = Color(hex: 0xFFFFFF)
    // MARK: 大胆版 (设计稿「首页 · 大胆版」)

    /// 高亮黄：翻牌最后一位、「正在攒」标签、选中的快捷项、主按钮上的图标。
    static let highlight = Color(hex: 0xFFE14D)
    /// 白干与超时的红：白干中头图标题、进度条超时格。
    static let hot = Color(hex: 0xFF5A3C)
    /// 上班中状态胶囊里的亮绿点。
    static let lime = Color(hex: 0xB6F24A)

    /// 分段控件选中块的投影 (设计稿 #1F1B161A，即 ink 10%)。
    static let shadow = ink.opacity(0.1)

    // MARK: 悬浮小牛 (设计稿方案 C 的存钱罐与金币彩带，直接写的色值)

    /// 硬币面。
    static let coin = Color(hex: 0xF5B82E)
    /// 硬币外圈描边。
    static let coinEdge = Color(hex: 0xB7791F)
    /// 硬币内圈。
    static let coinRing = Color(hex: 0xD9961A)
    /// 深一点的金币 (彩带里的 coin、coins)。
    static let coinDeep = Color(hex: 0xE0A21C)

    // MARK: 交互态 (设计稿没给，按上面的 token 推出来；用法见 `Components/Interaction.swift`)

    /// 悬停时叠在任意底色上的一层暖褐色 (#9B7B44 的 10%)：叠在 bg 上正好是 surface，
    /// 叠在 surface、白底、浅色底 (loss-soft 等) 上各自深一档，色相不跑偏。
    static let hoverOverlay = Color(hex: 0x9B7B44).opacity(0.10)
    /// 按下时叠的一层，比悬停再深一档 (同色 18%)。
    static let pressedOverlay = Color(hex: 0x9B7B44).opacity(0.18)
    /// 主按钮 (ink 底) 悬停：略浅。
    static let inkHover = Color(hex: 0x3A332B)
    /// 主按钮按下：略深。
    static let inkPressed = Color(hex: 0x0B0907)
    /// 输入框悬停 (未聚焦) 的描边。
    static let strokeHover = muted
}

extension Color {
    /// 由 0xRRGGBB 构造 sRGB 颜色 (`Palette` 与头图配色 `HeroTheme` 用)。
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
