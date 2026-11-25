import SwiftUI

/// 页面底部与弹窗里的按钮，经典版的样子 (同 `ThemeButtonStyle`)：圆角 8 的矩形、高 44、文字 13、图标 14 与文字同色。
/// 名字沿用大胆版的 `pill`，四种用途不变，外观按经典版归成两类：
/// - `ink`、`accent`：主操作 (请假、我还没走、终于下班了、加进队列)，墨色底、浅色字 13/600。
/// - `outline`：次操作 (今天扣钱了、算了)，surface 底、墨色字 13/500。
/// - `danger`：危险操作 (清空数据并重启)，surface 底、loss 色字。
/// 交互反馈同 `ThemeButtonStyle`：悬停手型，主按钮悬停略浅、按下略深，其余悬停、按下叠一层底色。
///
/// 用法：`Button { … } label: { Label { Text("请假") } icon: { PhosphorIcon(.umbrella) } }.buttonStyle(.pill(.ink))`
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case ink, outline, accent, danger
    }

    static let height: CGFloat = 44

    let kind: Kind
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonStyle { label, state in
            styled(label, state: state)
        }
        .makeBody(configuration: configuration)
    }

    private func styled(_ label: ButtonStyleConfiguration.Label, state: InteractionState) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return label
            .labelStyle(PillLabelStyle())
            .font(isSolid ? AppFont.bodySemibold : AppFont.bodyMedium)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Self.height)
            .background(fill(state), in: shape)
            .overlay {
                // surface 底的按钮悬停、按下时再叠一层，底色加深。
                if !isSolid { shape.fill(state.overlay) }
            }
            .contentShape(shape)
            .opacity(state.isEnabled ? 1 : 0.4)
    }

    /// 墨色实心 (主操作) 还是 surface 底。
    private var isSolid: Bool { kind == .ink || kind == .accent }

    private var foreground: Color {
        switch kind {
        case .ink, .accent: Palette.bg
        case .outline: Palette.ink
        case .danger: Palette.loss
        }
    }

    private func fill(_ state: InteractionState) -> Color {
        guard isSolid else { return Palette.surface }
        return state.isPressed ? Palette.inkPressed : state.isHovered ? Palette.inkHover : Palette.ink
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static func pill(_ kind: PillButtonStyle.Kind, fullWidth: Bool = true) -> PillButtonStyle {
        PillButtonStyle(kind: kind, fullWidth: fullWidth)
    }
}

/// 按钮里的 `Label`：图标 14pt，与文字同色，间隔 6。
private struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            configuration.icon
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14, height: 14)
                .iconOnTextBaseline(13)
            configuration.title
        }
    }
}
