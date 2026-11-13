import SwiftUI
import WageCore

/// 设置页的一组：12/700 muted 小标题，下面是卡片 (大胆版设计稿「设置」)。
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            Text(title).font(AppFont.ui(12, .bold)).foregroundStyle(Palette.muted)
            content()
        }
    }
}

/// 墨色细描边的圆角卡片 (圆角 16、底色 bg)，里面一行一行用 `InkCardDivider` 隔开。
struct InkCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r16)
        VStack(spacing: 0, content: content)
            .background(Palette.bg, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1))
    }
}

/// 卡片里两行之间的分隔线。
struct InkCardDivider: View {
    var body: some View {
        Palette.line.frame(height: 1)
    }
}

/// 卡片里可点开的一行：左边名称 (14 ink)，右边当前值 (13 号等宽) 与箭头；悬停、按下整行叠一层底，手型光标。
struct SettingsNavigationRow: View {
    let title: String
    /// 右侧的值，可以有多行 (如作息的上下班与饭点)，各行靠右对齐。
    let value: String
    /// 值用 ink 粗体 (本月工资)，否则 muted。
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s6) {
                Text(title).font(AppFont.ui(14)).foregroundStyle(Palette.ink)
                Spacer(minLength: Spacing.s8)
                Text(value)
                    .font(AppFont.num(13, emphasized ? .bold : .regular))
                    .foregroundStyle(emphasized ? Palette.ink : Palette.muted)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(Spacing.s2)
                PhosphorIcon(.caretRight, size: 13).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, Spacing.s14)
            .padding(.vertical, Spacing.s12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: 0))
    }
}

/// 菜单栏显示模式三个并排小块：上面是此刻会显示的数字 (粗体)，下面是模式名；选中的墨底黄字，其余浅底。
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
        let shape = RoundedRectangle(cornerRadius: Radius.r10)
        return Button { select(mode) } label: {
            VStack(spacing: Spacing.s2) {
                Text(previews[mode] ?? "—")
                    .font(AppFont.heavy(13))
                    .foregroundStyle(selected ? Palette.highlight : Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(mode.label)
                    .font(AppFont.ui(11))
                    .foregroundStyle(selected ? Color.white : Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(InteractiveButtonStyle { label, state in
            label
                .background(selected ? Palette.ink : Palette.surface, in: shape)
                .overlay(shape.fill(selected ? .clear : state.overlay))
                .contentShape(shape)
        })
        .disabled(selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 危险操作的胶囊 (清空数据并重启)：浅底红字、高 46，悬停、按下叠一层底。
struct DangerPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonStyle { label, state in
            label
                .font(AppFont.ui(14, .bold))
                .foregroundStyle(Palette.loss)
                .frame(maxWidth: .infinity, minHeight: PillButtonStyle.height)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().fill(state.overlay))
                .contentShape(Capsule())
        }
        .makeBody(configuration: configuration)
    }
}
