import SwiftUI

/// 设计稿 F5、F6 · 760 的表单外框：顶部页头 (返回箭头 18 + 标题 17/700，右侧日期 13)、中间内容 (间距 26)、
/// 底部按钮行 (按钮高 44、间距 10)，三段之间有分隔线。
/// 宽 360，与今日概览面板同宽。两种用法 (`FormSheetPlacement`，经环境传进来，表单本身不用管)：
/// - `.window`：在今日概览窗口里原地替换概览 (占满窗口，中间放不下时滚动，页头和按钮行不动)。
///   页头就是目标页那种 `PageHeader` (与红绿灯同一行，高 52，返回箭头笔画从 85、标题从 100 起)，日期在右侧，离图钉 12。
/// - `.sheet` (默认)：在历史单日详情里作为 sheet 弹出 (按内容高度)，没有红绿灯，页头从左边 20 排起，下面一条分隔线。
///
/// 用法：`FormSheet(title: "请假", subtitle: "11月5日 周四", back: dismiss) { 内容 } actions: { 按钮 }`
struct FormSheet<Content: View, Actions: View>: View {
    let title: String
    /// 右上角的日期；nil 时不显示。
    let subtitle: String?
    let back: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    @Environment(\.formSheetPlacement) private var placement

    /// 窗口里页头右侧的日期离窗口右沿 39 (图钉 20 宽、右边距 12，再空 7)，右沿落在 321。
    private static var windowTrailingInset: CGFloat { 39 }

    var body: some View {
        VStack(spacing: 0) {
            switch placement {
            case .window:
                PageHeader(title, back: back, isRoot: true) {
                    if let subtitle {
                        Text(subtitle).font(AppFont.body).foregroundStyle(Palette.muted)
                            .padding(.trailing, Self.windowTrailingInset - Spacing.screen)
                    }
                }
            case .sheet:
                head
                PanelDivider()
            }
            ScrollBody {
                VStack(alignment: .leading, spacing: PanelMetrics.formSectionGap) {
                    content()
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.vertical, Spacing.s24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            PanelDivider()
            HStack(spacing: Spacing.s10) {
                actions()
            }
            .padding(EdgeInsets(top: Spacing.s16, leading: Spacing.screen, bottom: Spacing.s18, trailing: Spacing.screen))
        }
        .frame(width: PanelMetrics.width)
        .background(Palette.bg)
    }

    private var head: some View {
        HStack(spacing: Spacing.s8) {
            Button(action: back) {
                PhosphorIcon(.caretLeft, size: 18)
                    .foregroundStyle(Palette.ink)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.highlight(radius: Radius.r6, outset: Spacing.s4))
            .help("返回")
            Text(title).font(AppFont.ui(17, .bold)).foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.s8)
            if let subtitle {
                Text(subtitle).font(AppFont.body).foregroundStyle(Palette.muted)
            }
        }
        .padding(EdgeInsets(top: Spacing.s14, leading: Spacing.screen, bottom: Spacing.s16, trailing: Spacing.screen))
    }
}

/// 表单外框放在哪里：今日概览窗口里原地打开，还是作为 sheet 弹出。
enum FormSheetPlacement {
    /// 今日概览窗口里，页头与红绿灯同一行。
    case window
    /// 弹出的 sheet，没有红绿灯。
    case sheet
}

extension EnvironmentValues {
    /// 下面的 `FormSheet` 怎么排页头；今日概览窗口给 `.window`，其余默认 `.sheet`。
    @Entry var formSheetPlacement: FormSheetPlacement = .sheet
}

/// 表单里的小标题 (13，muted)，如「为啥被扣 (可不选)」「时段」。
struct FormLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).font(AppFont.body).foregroundStyle(Palette.muted)
    }
}

