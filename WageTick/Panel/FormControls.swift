import SwiftUI

// 大胆版表单 (设计稿「弹窗-今天扣钱了」「弹窗-请假」) 的选择控件：配色只用墨色、白底与高亮黄。

/// 胶囊分段 (按金额 / 按日薪百分比)：surface 底的大胶囊，选中段墨色胶囊白字 14/700，其余 muted 14。
///
/// 用法：`BoldSegmented(selection: $method, options: [(.fixed, "按金额"), (.percent, "按日薪百分比")])`
struct BoldSegmented<ID: Hashable>: View {
    @Binding var selection: ID
    let options: [(value: ID, title: String)]

    private static var height: CGFloat { 44 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(AppFont.ui(14, selected ? .bold : .regular))
                        .foregroundStyle(selected ? .white : Palette.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(InteractiveButtonStyle { label, state in
                    label
                        .background(selected ? Palette.ink : state.overlay, in: Capsule())
                        .contentShape(Capsule())
                })
                .disabled(selected)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Spacing.s4)
        .frame(height: Self.height)
        .background(Palette.surface, in: Capsule())
    }
}

/// 一排等宽的小方块选项 (快捷金额、请假快捷时段)：高 34、圆角 12、1.5 墨色描边白底；选中墨色底、高亮黄字。
/// 悬停、按下叠一层底色 (选中的变浅、变深)。
struct BoldChoiceStyle: ButtonStyle {
    let selected: Bool
    var font: Font = AppFont.ui(13, .bold)

    static let height: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r12)
        return InteractiveButtonStyle { label, state in
            label
                .font(font)
                .foregroundStyle(selected ? Palette.highlight : Palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .background(fill(state), in: shape)
                .overlay {
                    shape.strokeBorder(Palette.ink, lineWidth: 1.5)
                    if !selected { shape.fill(state.overlay) }
                }
                .contentShape(shape)
        }
        .makeBody(configuration: configuration)
    }

    private func fill(_ state: InteractionState) -> Color {
        guard selected else { return Palette.card }
        if state.isPressed { return Palette.inkPressed }
        return state.isHovered ? Palette.inkHover : Palette.ink
    }
}

/// 带图标的大方块选项 (扣钱原因)：高 52、圆角 14，图标 18 在上、文字 13 在下；
/// 未选中白底 1.5 墨色描边，选中高亮黄底、2.5 墨色描边、文字加粗。
struct BoldTileStyle: ButtonStyle {
    let selected: Bool

    static let height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r14)
        return InteractiveButtonStyle { label, state in
            label
                .font(AppFont.ui(13, selected ? .bold : .regular))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .background(selected ? Palette.highlight : Palette.card, in: shape)
                .overlay {
                    shape.strokeBorder(Palette.ink, lineWidth: selected ? 2.5 : 1.5)
                    shape.fill(state.overlay)
                }
                .contentShape(shape)
        }
        .makeBody(configuration: configuration)
    }
}

/// 方块选项里的竖排内容：图标在上、文字在下。
struct TileLabel: View {
    let title: String
    let icon: Phosphor

    var body: some View {
        VStack(spacing: Spacing.s4) {
            PhosphorIcon(icon, size: 18)
            Text(title)
        }
    }
}
