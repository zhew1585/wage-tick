import SwiftUI

/// 设计稿的分段控件 (P5 单日详情「这天上不上班」、P6 设置「显示模式」)：
/// surface 底、圆角 9、内边距与段间距 3；选中段白底圆角 7 带轻投影、ink 12/600，其余 muted 12/400；
/// 每段可带一行 9 号等宽小字 (`subtitle`)。不可用的段变淡、点不动。
/// 未选中段悬停时文字变 ink、底色叠一层 hover，按下再深一档；选中段点不动，没有反馈。
///
/// 用法：`ThemeSegmented(options: modes.map { .init(id: $0, title: $0.label) }, selection: mode) { setMode($0) }`
/// 表单里直接绑定：`ThemeSegmented(selection: $method, options: [(.fixed, "按金额"), (.percent, "按日薪百分比")])`
struct ThemeSegmented<ID: Hashable>: View {
    struct Option: Identifiable {
        let id: ID
        let title: String
        var subtitle: String?
        var isEnabled = true
    }

    let options: [Option]
    let selection: ID?
    let select: (ID) -> Void
    /// 选项文字字号：默认 12，请假表单 13。
    var fontSize: CGFloat = 12

    init(options: [Option], selection: ID?, fontSize: CGFloat = 12, select: @escaping (ID) -> Void) {
        self.options = options
        self.selection = selection
        self.fontSize = fontSize
        self.select = select
    }

    /// 表单用：选中值直接绑定，每段只有标题。
    init(selection: Binding<ID>, options: [(value: ID, title: String)], fontSize: CGFloat = 12) {
        self.init(
            options: options.map { Option(id: $0.value, title: $0.title) },
            selection: selection.wrappedValue,
            fontSize: fontSize
        ) { selection.wrappedValue = $0 }
    }

    private static var disabledOpacity: Double { 0.5 }

    var body: some View {
        HStack(spacing: Spacing.s3) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(Spacing.s3)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r9))
    }

    private func segment(_ option: Option) -> some View {
        let selected = option.id == selection
        let shape = RoundedRectangle(cornerRadius: Radius.r7)
        return Button {
            select(option.id)
        } label: {
            VStack(spacing: Spacing.s1) {
                // 标题颜色由下面的样式按选中、悬停给。
                Text(option.title).font(AppFont.ui(fontSize, selected ? .semibold : .regular))
                if let subtitle = option.subtitle {
                    Text(subtitle).font(AppFont.num(9)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.vertical, option.subtitle == nil ? Spacing.s6 + 1 : Spacing.s6)
            .frame(maxWidth: .infinity)
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
                .contentShape(Rectangle())
        })
        // 选中段点不动 (不发 select、没有反馈)，但不按不可用变淡。
        .disabled(selected || !option.isEnabled)
        .opacity(option.isEnabled || selected ? 1 : Self.disabledOpacity)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
