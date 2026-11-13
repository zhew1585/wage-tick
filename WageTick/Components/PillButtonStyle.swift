import SwiftUI

/// 大胆版底部按钮 (设计稿「大胆风格」)：胶囊形、高 46、文字 14/700、图标 16。
/// - `ink`：墨色实心白字，主操作 (请假、我还没走、加进队列)；图标用高亮黄。
/// - `outline`：2pt 墨色描边，次操作 (今天扣钱了、算了)。
/// - `accent`：品牌橙实心白字 (终于下班了)。
/// 交互反馈同 `ThemeButtonStyle`：悬停手型，实心悬停略浅、按下略深，描边悬停、按下叠一层底色。
///
/// 用法：`Button { … } label: { Label { Text("请假") } icon: { PhosphorIcon(.umbrella) } }.buttonStyle(.pill(.ink))`
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case ink, outline, accent
    }

    static let height: CGFloat = 46

    let kind: Kind
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonStyle { label, state in
            label
                .labelStyle(PillLabelStyle(iconColor: iconColor))
                .font(AppFont.ui(14, .bold))
                .foregroundStyle(kind == .outline ? Palette.ink : Color.white)
                .lineLimit(1)
                .padding(.horizontal, Spacing.s16)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Self.height)
                .background(fill(state), in: Capsule())
                .overlay {
                    if kind == .outline {
                        Capsule().strokeBorder(Palette.ink, lineWidth: 2)
                        Capsule().fill(state.overlay)
                    }
                }
                .contentShape(Capsule())
                .opacity(state.isEnabled ? 1 : 0.4)
        }
        .makeBody(configuration: configuration)
    }

    private var iconColor: Color? {
        switch kind {
        case .ink: Palette.highlight
        case .outline: Palette.ink
        case .accent: .white
        }
    }

    private func fill(_ state: InteractionState) -> Color {
        switch kind {
        case .ink: state.isPressed ? Palette.inkPressed : state.isHovered ? Palette.inkHover : Palette.ink
        case .outline: .clear
        case .accent: state.isPressed ? Palette.accent.opacity(0.85) : state.isHovered ? Palette.accent.opacity(0.92) : Palette.accent
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillButtonStyle.Kind, fullWidth: Bool = true) -> PillButtonStyle {
        PillButtonStyle(kind: kind, fullWidth: fullWidth)
    }
}

/// 胶囊按钮里的 `Label`：图标 16pt 单独上色，与文字间隔 6。
private struct PillLabelStyle: LabelStyle {
    let iconColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.s6) {
            configuration.icon
                .font(.system(size: 14, weight: .bold))
                .frame(width: 16, height: 16)
                .foregroundStyle(iconColor ?? Palette.ink)
            configuration.title
        }
    }
}
