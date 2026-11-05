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

