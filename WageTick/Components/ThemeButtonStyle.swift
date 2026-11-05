import SwiftUI

/// 设计稿 Btn/Primary (墨色底、浅色字 13/600) 与 Btn/Secondary (surface 底、墨色字 13/500)：
/// 高 37、左右内边距 14、圆角 8，图标 14pt 与文字间隔 6。
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

    let kind: Kind
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        ThemeButton(configuration: configuration, kind: kind, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == ThemeButtonStyle {
    static var primary: ThemeButtonStyle { ThemeButtonStyle(kind: .primary) }
    static var secondary: ThemeButtonStyle { ThemeButtonStyle(kind: .secondary) }

    static func primary(fullWidth: Bool) -> ThemeButtonStyle { ThemeButtonStyle(kind: .primary, fullWidth: fullWidth) }
    static func secondary(fullWidth: Bool) -> ThemeButtonStyle { ThemeButtonStyle(kind: .secondary, fullWidth: fullWidth) }
}

/// 单独成视图才能读到 `isEnabled`：不可用时整体变淡。
private struct ThemeButton: View {
    let configuration: ButtonStyleConfiguration
    let kind: ThemeButtonStyle.Kind
    let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled

    private static let pressedOpacity = 0.8
    private static let disabledOpacity = 0.4

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        configuration.label
            .labelStyle(ThemeButtonLabelStyle())
            .font(kind == .primary ? AppFont.bodySemibold : AppFont.bodyMedium)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: ThemeButtonStyle.height)
            .background(kind == .primary ? Palette.ink : Palette.surface, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? Self.pressedOpacity : 1) : Self.disabledOpacity)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.bg
        case .secondary: configuration.role == .destructive ? Palette.loss : Palette.ink
        }
    }
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
