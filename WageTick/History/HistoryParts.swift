import SwiftUI
import WageCore

/// 历史三页 (月列表、月日历、单日详情) 共用的大胆版小件：头图标题栏右侧的小胶囊、单日详情的分段标题与记录卡、
/// 「这天上不上班」的胶囊分段、月日历底部固定的小结。配色只用墨色、头图主色 (`HeroTheme.ledger`) 与少量高亮黄。

/// 头图收起后窄栏里的小号金额：「¥571.43」取「¥571」。
func heroCompactMoney(_ text: String) -> String {
    let parts = HeroAmount.split(text)
    return (parts.currency ?? "") + parts.integer
}

/// 头图标题栏一行右侧的小胶囊按钮 (与返回胶囊同一套半透明底)：只放图标或图标 + 文字，如月日历的上下月、改工资。
/// 放在 `BoldHero` 上面的 `overlay(alignment: .topTrailing)` 里，高度对齐标题栏 (见 `HeroTitlebarTrailing`)。
struct HeroChipButton: View {
    let icon: Phosphor
    var title: String?
    let help: String
    var isEnabled = true
    let theme: HeroTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                PhosphorIcon(icon, size: 13).iconOnTextBaseline(12)
                if let title { Text(title).font(AppFont.ui(12, .bold)) }
            }
            .foregroundStyle(theme.onChip)
            .padding(EdgeInsets(top: 3, leading: Spacing.s8, bottom: 3, trailing: title == nil ? Spacing.s8 : Spacing.s10))
            .background(theme.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor(isEnabled)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
    }
}

/// 把一排 `HeroChipButton` 摆到头图标题栏一行的右侧 (与返回胶囊同一行，收起后也还在)。
struct HeroTitlebarTrailing<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: Spacing.s6) { content() }
            .frame(height: WindowChrome.Titlebar.standard.height)
            .padding(.trailing, Spacing.screen)
    }
}

/// 单日详情的一块：左边 14/700 标题，右上角橙色「+ 补记…」(没有入口时不显示)，下面是记录卡或空行。
struct HistorySection<Content: View>: View {
    struct Add {
        let title: String
        let action: () -> Void
    }

    let title: String
    let add: Add?
    @ViewBuilder let content: () -> Content

    init(_ title: String, add: Add? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.add = add
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            HStack(spacing: Spacing.s8) {
                Text(title).font(AppFont.ui(14, .bold)).foregroundStyle(Palette.ink)
                Spacer(minLength: Spacing.s8)
                if let add {
                    Button(action: add.action) {
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
                            PhosphorIcon(.plus, size: 12).iconOnTextBaseline(13)
                            Text(add.title).font(AppFont.ui(13, .bold))
                        }
                        .foregroundStyle(Palette.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.highlight(radius: Radius.r6, outset: Spacing.s4))
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 一条记录 (扣钱、请假、白干)：1.5pt 墨色描边的圆角卡，左边标题 14/600 与一行 muted 说明，右边粗体数值。
/// 点一下修改 (`edit` 为 nil 时点不动)，悬停时数值左边出现删除或撤销 (`delete`)。
struct RecordCard: View {
    let title: String
    let detail: String?
    let value: String
    var valueColor = Palette.ink
    /// 标题用等宽字 (白干的时段)。
    var monospacedTitle = false
    /// 删除按钮的图标与说明：能改的记录是「删除」，只能撤销的是「撤销」。
    var deleteHelp = "删除"
    let edit: (() -> Void)?
    let delete: (() -> Void)?

    @State private var hovering = false

    private static let shape = RoundedRectangle(cornerRadius: Radius.r14)

    var body: some View {
        HStack(spacing: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text(title)
                    .font(monospacedTitle ? AppFont.num(14, .semibold) : AppFont.ui(14, .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail).font(AppFont.caption).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: Spacing.s8)
            if hovering, let delete {
                IconButton(systemName: deleteHelp == "删除" ? "trash" : "arrow.uturn.backward", help: deleteHelp, action: delete)
            }
            Text(value).font(AppFont.heavy(15)).foregroundStyle(valueColor).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, Spacing.s14)
        .padding(.vertical, Spacing.s12)
        .frame(minHeight: 60)
        .background(Palette.bg, in: Self.shape)
        .overlay(Self.shape.strokeBorder(Palette.ink, lineWidth: 1.5))
        .contentShape(Self.shape)
        .onTapGesture { edit?() }
        .hoverFeedback(cornerRadius: Radius.r14, isEnabled: edit != nil)
        .onHover { hovering = $0 }
        .help(edit == nil ? "" : "点一下修改")
    }
}

/// 段里没有记录时的一行：surface 底圆角块，muted 字，如「没请假」或入口不可用的原因。
struct EmptyRecord: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(AppFont.body)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s14)
            .padding(.vertical, Spacing.s12)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r14))
    }
}

/// 胶囊分段 (单日详情「这天上不上班」)：surface 胶囊底，选中段墨色胶囊白字 14/700，其余 muted 14。
/// 不可用的段变淡、点不动；选中段点不动。未选中段悬停时字变墨色、叠一层底。
struct PillSegmented<ID: Hashable>: View {
    struct Option: Identifiable {
        let id: ID
        let title: String
        var isEnabled = true
    }

    let options: [Option]
    let selection: ID
    let select: (ID) -> Void

    var body: some View {
        HStack(spacing: Spacing.s4) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(Spacing.s4)
        .background(Palette.surface, in: Capsule())
    }

    private func segment(_ option: Option) -> some View {
        let selected = option.id == selection
        return Button {
            select(option.id)
        } label: {
            Text(option.title)
                .font(AppFont.ui(14, selected ? .bold : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(InteractiveButtonStyle { label, state in
            label
                .foregroundStyle(selected ? Color.white : state.isHovered ? Palette.ink : Palette.muted)
                .background(selected ? Palette.ink : state.overlay, in: Capsule())
                .contentShape(Capsule())
        })
        .disabled(selected || !option.isEnabled)
        .opacity(option.isEnabled || selected ? 1 : 0.5)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 月日历底部固定的一行小结 (扣款、请假、白干)：等宽几栏，粗体数值 (扣款不为零时亏钱色) 下面 muted 小标题，栏间细竖线；上沿一条分隔线。
struct HistoryStatsBar: View {
    let figures: [HistoryFigure]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(figures.enumerated()), id: \.offset) { index, figure in
                if index > 0 {
                    Rectangle().fill(Palette.line).frame(width: 1, height: 30)
                }
                VStack(spacing: Spacing.s2) {
                    Text(figure.value)
                        .font(AppFont.heavy(16))
                        .foregroundStyle(figure.isLoss ? Palette.loss : Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(figure.title).font(AppFont.small).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s12)
        .background(Palette.bg)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}
