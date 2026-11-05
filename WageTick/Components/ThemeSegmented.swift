import SwiftUI

/// 设计稿的分段控件 (P5 单日详情「这天上不上班」、P6 设置「显示模式」)：
/// surface 底、圆角 9、内边距与段间距 3；选中段白底圆角 7 带轻投影、ink 12/600，其余 muted 12/400；
/// 每段可带一行 9 号等宽小字 (`subtitle`)。不可用的段变淡、点不动。
/// 未选中段悬停时文字变 ink、底色叠一层 hover，按下再深一档；选中段点不动，没有反馈。
///
/// 用法：`ThemeSegmented(options: modes.map { .init(id: $0, title: $0.label) }, selection: mode) { setMode($0) }`
/// 表单里直接绑定：`ThemeSegmented(selection: $method, options: [(.fixed, "按金额"), (.percent, "按日薪百分比")])`
/// 760 设计稿扣钱、请假表单的大号分段 (13 号字、段高更高、11 号等宽小字)：传 `size: .large`。
struct ThemeSegmented<ID: Hashable>: View {
    struct Option: Identifiable {
        let id: ID
        let title: String
        var subtitle: String?
        var isEnabled = true
    }

    /// 段的尺寸：`regular` 为 P5、P6 的小号；`large` 为 760 设计稿 F5、F6 表单里的大号。
    enum Size {
        case regular, large
    }

    let options: [Option]
    let selection: ID?
    let select: (ID) -> Void
    /// 选项文字字号：默认 12；`size: .large` 时固定 13，忽略此值。
    var fontSize: CGFloat = 12
    var size: Size = .regular

    init(options: [Option], selection: ID?, fontSize: CGFloat = 12, size: Size = .regular, select: @escaping (ID) -> Void) {
        self.options = options
        self.selection = selection
        self.fontSize = fontSize
        self.size = size
        self.select = select
    }

    /// 表单用：选中值直接绑定，每段只有标题。
    init(selection: Binding<ID>, options: [(value: ID, title: String)], fontSize: CGFloat = 12, size: Size = .regular) {
        self.init(
            options: options.map { Option(id: $0.value, title: $0.title) },
            selection: selection.wrappedValue,
            fontSize: fontSize,
            size: size
        ) { selection.wrappedValue = $0 }
    }

    /// 段内上下内边距：大号无小字 10、带小字 11 (设计稿 F5、F6 · 760)；小号无小字 7、带小字 6。
    private func verticalPadding(hasSubtitle: Bool) -> CGFloat {
        switch size {
        case .regular: hasSubtitle ? Spacing.s6 : Spacing.s6 + 1
        case .large: hasSubtitle ? 11 : Spacing.s10
        }
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
            VStack(spacing: size == .large ? Spacing.s2 : Spacing.s1) {
                // 标题颜色由下面的样式按选中、悬停给。
                Text(option.title).font(AppFont.ui(size == .large ? 13 : fontSize, selected ? .semibold : .regular))
                if let subtitle = option.subtitle {
                    Text(subtitle).font(AppFont.num(size == .large ? 11 : 9)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.vertical, verticalPadding(hasSubtitle: option.subtitle != nil))
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
