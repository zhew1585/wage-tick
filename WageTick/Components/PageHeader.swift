import SwiftUI

/// 设计稿子页面 (P3 至 P6 · 760) 的页头：标题 (17/700)，右边可放说明或操作，
/// 高 52 (与 `.tall` 标题栏同高，红绿灯正好垂直居中)，下沿一条分隔线。
/// 页头和系统红绿灯排在同一行 (见 `PageWindow`)，左边让出红绿灯的位置。
/// 窗口的首页 (目标、历史、设置) 只有标题，关窗用系统红绿灯 (issue #17：返回箭头其实是关窗，容易误导)；
/// 下一级页面 (月日历、单日详情) 标题前带返回箭头 (Phosphor caret-left 18)，回到上一级，esc 等同返回。返回按钮悬停、按下时外扩一圈圆角底。
///
/// 用法：
/// - 首页：`PageHeader("目标")`、右侧放东西：`PageHeader("历史") { Text("按月倒序") }`
/// - 下一级：`PageHeader("10月", back: { selected = nil })`
struct PageHeader<Trailing: View>: View {
    let title: String
    /// 回到上一级；nil 表示窗口首页，不显示返回箭头。
    let back: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    private static var height: CGFloat { WindowChrome.Titlebar.tall.height }
    private static var iconSize: CGFloat { 18 }

    init(_ title: String, back: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.back = back
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Spacing.s8) {
            if let back {
                Button(action: back) {
                    HStack(spacing: Spacing.s8) {
                        PhosphorIcon(.caretLeft, size: Self.iconSize)
                        titleText
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.highlight(radius: Radius.r6, outset: Spacing.s4))
                .keyboardShortcut(.cancelAction)
                .help("返回")
            } else {
                titleText
            }
            Spacer(minLength: Spacing.s8)
            trailing()
        }
        .padding(.leading, WindowChrome.Titlebar.tall.leadingInset)
        .padding(.trailing, Spacing.screen)
        .frame(height: Self.height)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    private var titleText: some View {
        Text(title).font(AppFont.pageTitle).lineLimit(1).foregroundStyle(Palette.ink)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, back: (() -> Void)? = nil) {
        self.init(title, back: back) { EmptyView() }
    }
}

/// 页面里一组内容的小标题 (目标页「攒钱队列 4」、设置页「钱与作息」)。
/// `count` 给了时在标题后面跟一个等宽小数字；`tracking` 是字距 (设置页 0.5)。
struct GroupLabel: View {
    let title: String
    var count: Int?
    var font: Font = AppFont.captionSemibold
    var tracking: CGFloat = 0

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Text(title).font(font).tracking(tracking)
            if let count {
                Text("\(count)").font(AppFont.numSmall)
            }
        }
        .foregroundStyle(Palette.muted)
    }
}

/// 白底、line 描边的圆角卡片，里面一行一行用 `CardDivider` 隔开 (设置页、目标排队列表)。
struct CardBox<Content: View>: View {
    var radius: CGFloat = Radius.r10
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        VStack(spacing: 0, content: content)
            .background(Palette.card, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// 卡片里两行之间的分隔线。
struct CardDivider: View {
    var body: some View {
        Palette.line.frame(height: 1)
    }
}
