import SwiftUI

/// 设计稿的分段控件 (P5 单日详情「这天上不上班」、P6 设置「显示模式」)：
/// surface 底、圆角 9、内边距与段间距 3；选中段白底圆角 7 带轻投影、ink 12/600，其余 muted 12/400；
/// 每段可带一行 9 号等宽小字 (`subtitle`)。不可用的段变淡、点不动。
///
/// 用法：`ThemeSegmented(options: modes.map { .init(id: $0, title: $0.label) }, selection: mode) { setMode($0) }`
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
        return Button {
            if !selected { select(option.id) }
        } label: {
            VStack(spacing: Spacing.s1) {
                Text(option.title)
                    .font(selected ? AppFont.captionSemibold : AppFont.caption)
                    .foregroundStyle(selected ? Palette.ink : Palette.muted)
                if let subtitle = option.subtitle {
                    Text(subtitle).font(AppFont.num(9)).foregroundStyle(Palette.muted)
                }
            }
            .padding(.vertical, option.subtitle == nil ? Spacing.s6 + 1 : Spacing.s6)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Radius.r7)
                        .fill(Palette.card)
                        .shadow(color: Palette.shadow, radius: 1.5, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 选中段本来就点不动，不按不可用变淡。
        .disabled(!option.isEnabled && !selected)
        .opacity(option.isEnabled || selected ? 1 : Self.disabledOpacity)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
