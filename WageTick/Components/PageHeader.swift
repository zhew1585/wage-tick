import SwiftUI

/// 设计稿子页面 (P3 至 P6 · 760) 的页头：标题 (17/700)，右边可放说明或操作，
/// 高 52 (与 `.tall` 标题栏同高，红绿灯正好垂直居中)，下沿一条分隔线。
/// 这些页面在今日概览窗口里从右边推进来 (ADR-0005 的 2026-11-13、2026-11-25 补充)，顶到窗口上沿，
/// 页头和系统红绿灯排在同一行，返回与标题在这 52 高里垂直居中，左边让出红绿灯的位置。
/// 标题前带返回箭头 (Phosphor caret-left 18)，esc 等同返回；返回按钮悬停、按下时外扩一圈圆角底。`back` 为 nil 时只有标题。
/// 两种排法：
/// - 页面的首页 (目标、历史月列表、设置，`isRoot`)：原版这里只有标题，从 85 排起。现在返回箭头收在红绿灯与标题之间，
///   箭头的笔画离红绿灯 5，标题只比原版靠右 4.5，整组不往右挤。返回回到概览。
/// - 下一级页面 (月日历、单日详情)：同原版，箭头从 85 排起，标题跟在后面 (间距 8)。返回回到上一级。
///
/// 用法：
/// - 首页：`PageHeader("目标", back: close, isRoot: true)`、右侧放东西：`PageHeader("历史", back: close, isRoot: true) { Text("按月倒序") }`
/// - 下一级：`PageHeader("10月", back: { selected = nil })`
struct PageHeader<Trailing: View>: View {
    let title: String
    /// 回到上一级；nil 时不显示返回箭头。
    let back: (() -> Void)?
    /// 页面的首页：返回箭头收紧，标题留在原版的位置附近 (见上)。
    let isRoot: Bool
    @ViewBuilder let trailing: () -> Trailing

    private static var height: CGFloat { WindowChrome.Titlebar.tall.height }
    private static var iconSize: CGFloat { 18 }
    /// 首页的排法：整组从 79 排起 (原版标题的 85 往左 6)；箭头图标 18 宽里笔画只占中间约 6，只给它留 6 宽，
    /// 笔画落在 78 至 84.5，离红绿灯右沿 (73) 5；再空 4.5 是标题，从 89.5 排起，笔画与标题之间空 5。
    private static var rootLeading: CGFloat { WindowChrome.Titlebar.tall.leadingInset - Spacing.s6 }
    private static var rootIconWidth: CGFloat { 6 }
    private static var rootSpacing: CGFloat { Spacing.s4 + 0.5 }

    init(_ title: String, back: (() -> Void)? = nil, isRoot: Bool = false, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.back = back
        self.isRoot = isRoot
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Spacing.s8) {
            if let back {
                Button(action: back) {
                    HStack(spacing: isRoot ? Self.rootSpacing : Spacing.s8) {
                        PhosphorIcon(.caretLeft, size: Self.iconSize)
                            .frame(width: isRoot ? Self.rootIconWidth : nil)
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
        .padding(.leading, isRoot ? Self.rootLeading : WindowChrome.Titlebar.tall.leadingInset)
        .padding(.trailing, Spacing.screen)
        .frame(height: Self.height)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    private var titleText: some View {
        Text(title).font(AppFont.pageTitle).lineLimit(1).foregroundStyle(Palette.ink)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, back: (() -> Void)? = nil, isRoot: Bool = false) {
        self.init(title, back: back, isRoot: isRoot) { EmptyView() }
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
