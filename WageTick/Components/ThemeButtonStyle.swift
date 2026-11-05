import SwiftUI

/// 设计稿 Btn/Primary (墨色底、浅色字 13/600) 与 Btn/Secondary (surface 底、墨色字 13/500)：
/// 高 37、左右内边距 14、圆角 8，图标 14pt 与文字间隔 6。
/// 交互反馈 (见 `Interaction.swift`)：悬停手型；主按钮悬停略浅、按下略深，次要按钮悬停、按下底色逐级加深；不可用时整体变淡、没有反馈。
///
/// 用法：
/// - `Button("下一步") { … }.buttonStyle(.primary)`
/// - 带图标：`Button { … } label: { Label("请假", systemImage: "umbrella") }.buttonStyle(.secondary)`
/// - 图标单独上色：`Label { Text("今天扣钱了") } icon: { Image(systemName: "chart.line.downtrend.xyaxis").foregroundStyle(Palette.loss) }`
/// - 占满宽度：`.buttonStyle(.primary(fullWidth: true))`
/// - `role: .destructive` 的次要按钮文字用 `Palette.loss`。
struct ThemeButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary
    }

    /// 按钮固定高度，排版需要给按钮留位置时用 (如面板情绪按钮行)。
    static let height: CGFloat = 37
    private static let disabledOpacity = 0.4

    let kind: Kind
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonStyle { label, state in
            themed(label, role: configuration.role, state: state)
        }
        .makeBody(configuration: configuration)
    }

    private func themed(_ label: ButtonStyleConfiguration.Label, role: ButtonRole?, state: InteractionState) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return label
            .labelStyle(ThemeButtonLabelStyle())
            .font(kind == .primary ? AppFont.bodySemibold : AppFont.bodyMedium)
            .foregroundStyle(foreground(role: role))
            .lineLimit(1)
            .padding(.horizontal, Spacing.s14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: ThemeButtonStyle.height)
            .background(background(state), in: shape)
            .overlay {
                // 次要按钮的悬停、按下：surface 底上再叠一层，底色加深。
                if kind == .secondary { shape.fill(state.overlay) }
            }
            .contentShape(shape)
            .opacity(state.isEnabled ? 1 : Self.disabledOpacity)
    }

    private func background(_ state: InteractionState) -> Color {
        switch kind {
        case .primary: state.isPressed ? Palette.inkPressed : state.isHovered ? Palette.inkHover : Palette.ink
        case .secondary: Palette.surface
        }
    }

    private func foreground(role: ButtonRole?) -> Color {
        switch kind {
        case .primary: Palette.bg
        case .secondary: role == .destructive ? Palette.loss : Palette.ink
        }
    }
}

extension ButtonStyle where Self == ThemeButtonStyle {
    static var primary: ThemeButtonStyle { ThemeButtonStyle(kind: .primary) }
    static var secondary: ThemeButtonStyle { ThemeButtonStyle(kind: .secondary) }

    static func primary(fullWidth: Bool) -> ThemeButtonStyle { ThemeButtonStyle(kind: .primary, fullWidth: fullWidth) }
    static func secondary(fullWidth: Bool) -> ThemeButtonStyle { ThemeButtonStyle(kind: .secondary, fullWidth: fullWidth) }
}

/// 按钮里的 `Label`：图标 14pt，与文字间隔 6。
private struct ThemeButtonLabelStyle: LabelStyle {
    private static let iconSize: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.s6) {
            configuration.icon
                .font(.system(size: 12, weight: .semibold))
                .frame(width: Self.iconSize, height: Self.iconSize)
            configuration.title
        }
    }
}
