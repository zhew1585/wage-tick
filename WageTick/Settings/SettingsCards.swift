import SwiftUI
import WageCore

/// 设置页的一组 (经典视觉)：11/600 muted 小标题 (字距 0.5)，下面是卡片。
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(title).font(AppFont.ui(11, .semibold)).tracking(0.5).foregroundStyle(Palette.muted)
            content()
        }
    }
}

/// 圆角卡片 (同经典 CardBox：白底、圆角 10、line 描边)，里面一行一行用 `InkCardDivider` 隔开。
struct InkCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r10)
        VStack(spacing: 0, content: content)
            .background(Palette.card, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// 卡片里两行之间的分隔线。
struct InkCardDivider: View {
    var body: some View {
        Palette.line.frame(height: 1)
    }
}

/// 卡片里可点开的一行：左边名称 (13 ink)，右边当前值 (12 号等宽) 与箭头；悬停、按下整行叠一层底，手型光标。
struct SettingsNavigationRow: View {
    let title: String
    /// 右侧的值，可以有多行 (如作息的上下班与饭点)，各行靠右对齐。
    let value: String
    /// 值用 ink 色 (本月工资)，否则 muted。
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s4) {
                Text(title).font(AppFont.body).foregroundStyle(Palette.ink)
                Spacer(minLength: Spacing.s8)
                Text(value)
                    .font(AppFont.num(12, emphasized ? .semibold : .regular))
                    .foregroundStyle(emphasized ? Palette.ink : Palette.muted)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(Spacing.s2)
                PhosphorIcon(.caretRight, size: 12).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, Spacing.s14)
            .padding(.vertical, Spacing.s10 + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: 0))
    }
}

/// 菜单栏显示模式三个并排小块：上面是此刻会显示的数字 (等宽 13/600)，下面是模式名 11 muted；
/// 选中的白底、1.5 墨色描边，其余 surface 底 (同表单的选项方块)。
struct MenuBarModeTiles: View {
    let previews: [MenuBarMode: String]
    let selection: MenuBarMode
    let select: (MenuBarMode) -> Void

    var body: some View {
        HStack(spacing: Spacing.s6) {
            ForEach(MenuBarMode.allCases, id: \.self, content: tile)
        }
    }

    private func tile(_ mode: MenuBarMode) -> some View {
        let selected = mode == selection
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return Button { select(mode) } label: {
            VStack(spacing: Spacing.s2) {
                Text(previews[mode] ?? "—")
                    .font(AppFont.num(13, .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(mode.label)
                    .font(AppFont.ui(11))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(InteractiveButtonStyle { label, state in
            label
                .background(selected ? Palette.card : Palette.surface, in: shape)
                .overlay {
                    if selected { shape.strokeBorder(Palette.ink, lineWidth: 1.5) }
                    shape.fill(selected ? .clear : state.overlay)
                }
                .contentShape(shape)
        })
        .disabled(selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 危险操作的按钮 (清空数据并重启)：surface 底、loss 字 13/600、圆角 8、高 44 (同 `PillButtonStyle` 的危险样式)，悬停、按下叠一层底。
struct DangerPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonStyle { label, state in
            label
                .font(AppFont.bodySemibold)
                .foregroundStyle(Palette.loss)
                .frame(maxWidth: .infinity, minHeight: PillButtonStyle.height)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).fill(state.overlay))
                .contentShape(RoundedRectangle(cornerRadius: Radius.control))
        }
        .makeBody(configuration: configuration)
    }
}
