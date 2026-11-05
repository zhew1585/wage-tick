import SwiftUI

/// 面板底部入口栏 (PRD F4 第 8 条，设计稿 P2 Footer)：surface 底，左边历史、目标、设置，右边老板路过快捷键。
struct PanelFooter: View {
    /// 老板路过快捷键，如「⌃⌥B」。
    let bossHotkey: String?
    let openHistory: () -> Void
    let openGoals: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            FooterItem(icon: .calendarBlank, title: "历史", action: openHistory)
            FooterItem(icon: .flagBanner, title: "目标", action: openGoals)
            FooterItem(icon: .gearSix, title: "设置", action: openSettings)
            Spacer()
            if let bossHotkey {
                HStack(spacing: Spacing.s4) {
                    PhosphorIcon(.eyeSlash, size: 13)
                    Text(bossHotkey).font(AppFont.numSmall)
                }
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, Spacing.s8)
                .help("老板路过")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("老板路过 \(bossHotkey)")
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s10)
        .background(Palette.surface)
    }
}

/// 入口栏的一项：图标 14 + 文字 12，muted；悬停时浅色底。
private struct FooterItem: View {
    let icon: Phosphor
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                PhosphorIcon(icon, size: 14)
                Text(title).font(AppFont.caption)
            }
            .foregroundStyle(hovering ? Palette.ink : Palette.muted)
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s6)
            .background(hovering ? Palette.line.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.r6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
