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
    /// 分段控件选中块的投影 (设计稿 #1F1B161A，即 ink 10%)。
    static let shadow = ink.opacity(0.1)
    /// 示意用的系统菜单栏底色 (引导第 3 步的菜单栏预览，设计稿里直接写的 #E9E6E1)。
    static let menuBarMock = Color(hex: 0xE9E6E1)

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

private extension Color {
    /// 由 0xRRGGBB 构造 sRGB 颜色。
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
