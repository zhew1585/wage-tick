import SwiftUI

/// 设计稿 F5、F6 的表单外框：顶部 Sheet Head (返回箭头 + 标题，右侧日期)、中间内容、底部按钮行，三段之间有分隔线。
/// 宽 360，与今日概览面板同宽：在面板里原地替换面板内容，在历史单日详情里作为 sheet 弹出。
///
/// 用法：`FormSheet(title: "请假", subtitle: "11月5日 周四", back: dismiss) { 内容 } actions: { 按钮 }`
struct FormSheet<Content: View, Actions: View>: View {
    let title: String
    /// 右上角的日期；nil 时不显示。
    let subtitle: String?
    let back: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            head
            PanelDivider()
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            PanelDivider()
            HStack(spacing: Spacing.s8) {
                actions()
            }
            .padding(EdgeInsets(top: Spacing.s14, leading: Spacing.screen, bottom: 18, trailing: Spacing.screen))
        }
        .frame(width: PanelMetrics.width)
        .background(Palette.bg)
    }

    private var head: some View {
        HStack(spacing: Spacing.s8) {
            Button(action: back) {
                PhosphorIcon(.caretLeft, size: 16)
                    .foregroundStyle(Palette.ink)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("返回")
            Text(title).font(AppFont.sheetTitle).foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.s8)
            if let subtitle {
                Text(subtitle).font(AppFont.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s16)
    }
}

/// 表单里的小标题 (12，muted)，如「为啥被扣 (可不选)」「时段」。
struct FormLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).font(AppFont.caption).foregroundStyle(Palette.muted)
    }
}

/// 设计稿的分段选择：surface 底、圆角 9、内边距 3；选中项白底、圆角 7、带一点投影，文字加粗变墨色。
/// 用法：`ThemeSegmented(selection: $method, options: [(.fixed, "按金额"), (.percent, "按日薪百分比")])`
struct ThemeSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    /// 选项文字字号：扣钱表单 12，请假表单 13。
    var fontSize: CGFloat = 12

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                segment(option.value, title: option.title)
            }
        }
        .padding(3)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 9))
    }

    private func segment(_ value: Value, title: String) -> some View {
        let selected = value == selection
        return Button {
            selection = value
        } label: {
            Text(title)
                .font(AppFont.ui(fontSize, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.ink : Palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Palette.card)
                            .shadow(color: Palette.ink.opacity(0.1), radius: 1.5, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
