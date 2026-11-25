import SwiftUI

// 扣钱、请假表单的选择控件 (经典视觉，同 nightly.20261112.15 的 ThemeSegmented、Field)：
// surface 底，选中的白底带淡投影或墨色描边；不用墨色实心块与高亮黄。

/// 分段 (按金额 / 按日薪百分比)：surface 底、圆角 9、内边距与段间距 3，高 44；
/// 选中段白底圆角 7 带淡投影、墨色 13/600，其余 muted 13；未选中段悬停文字变墨色、叠一层 hover。
///
/// 用法：`BoldSegmented(selection: $method, options: [(.fixed, "按金额"), (.percent, "按日薪百分比")])`
struct BoldSegmented<ID: Hashable>: View {
    @Binding var selection: ID
    let options: [(value: ID, title: String)]

    private static var height: CGFloat { 44 }

    var body: some View {
        HStack(spacing: Spacing.s3) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                let shape = RoundedRectangle(cornerRadius: Radius.r7)
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(AppFont.ui(13, selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(InteractiveButtonStyle { label, state in
                    label
                        .foregroundStyle(selected || state.isHovered ? Palette.ink : Palette.muted)
                        .background {
                            if selected {
                                shape.fill(Palette.card).shadow(color: Palette.shadow, radius: 1.5, y: 1)
                            } else {
                                shape.fill(state.overlay)
                            }
                        }
                        .contentShape(shape)
                })
                .disabled(selected)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Spacing.s3)
        .frame(height: Self.height)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r9))
    }
}

/// 一排等宽的小方块选项 (快捷金额、请假快捷时段)：高 34、圆角 8；未选中 surface 底墨色字，
/// 选中白底、1.5 墨色描边、字加粗。悬停、按下叠一层底色。
struct BoldChoiceStyle: ButtonStyle {
    let selected: Bool
    var font: Font = AppFont.ui(13, .medium)

    static let height: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return InteractiveButtonStyle { label, state in
            label
                .font(font)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .background(selected ? Palette.card : Palette.surface, in: shape)
                .overlay {
                    if selected { shape.strokeBorder(Palette.ink, lineWidth: 1.5) }
                    shape.fill(state.overlay)
                }
                .contentShape(shape)
        }
        .makeBody(configuration: configuration)
    }
}

/// 带图标的大方块选项 (扣钱原因)：高 52、圆角 8，图标 18 在上、文字 13 在下；
/// 未选中 surface 底，选中白底、1.5 墨色描边、文字加粗。
struct BoldTileStyle: ButtonStyle {
    let selected: Bool

    static let height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return InteractiveButtonStyle { label, state in
            label
                .font(AppFont.ui(13, selected ? .semibold : .regular))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .background(selected ? Palette.card : Palette.surface, in: shape)
                .overlay {
                    if selected { shape.strokeBorder(Palette.ink, lineWidth: 1.5) }
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
