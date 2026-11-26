import SwiftUI

/// 设计稿子页面 (P3 至 P6 · 760) 的页头：标题 (17/700)，右边可放说明或操作，
/// 高 52 (与 `.tall` 标题栏同高，红绿灯正好垂直居中)，下沿一条分隔线。
/// 这些页面在今日概览窗口里从右边推进来 (ADR-0005 的 2026-11-13、2026-11-25 补充)，顶到窗口上沿，
/// 页头和系统红绿灯排在同一行，返回与标题在这 52 高里垂直居中，左边让出红绿灯的位置。
/// 标题前带返回箭头 (Phosphor caret-left 18)，esc 等同返回；返回按钮悬停、按下时外扩一圈圆角底。`back` 为 nil 时只有标题。
/// 两种排法：
/// - 页面的首页 (目标、历史月列表、设置，`isRoot`)：原版这里只有标题，从 85 排起 (红绿灯右边空 12)。
///   现在整组仍从这条线起：返回箭头的笔画落在 85，离红绿灯和原版一样远；标题让出箭头 (笔画宽 7) 再空 8，从 100 排起。
///   8 是红绿灯三个圆之间的间距，箭头和标题看着是一组，和红绿灯是两组。返回回到概览。
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
    /// 首页的排法：箭头图标 18 宽里笔画只占 5 至 12 这 7 宽，只给它留 6 宽的位置 (图标居中，笔画左沿比这 6 宽的左沿靠左 1、右沿齐平)。
    /// 整组从 86 排起，笔画正好落在 85 至 92：85 就是原版标题起点，离红绿灯右沿 (真窗口里实测 72) 13；
    /// 再空 8 是标题，从 100 排起，比原版靠右 15 (下一级页面的原版排法是靠右 26)。间距都是整数，1 倍屏上也落在整像素。
    private static var rootLeading: CGFloat { WindowChrome.Titlebar.tall.leadingInset + Spacing.s1 }
    private static var rootIconWidth: CGFloat { 6 }
    private static var rootSpacing: CGFloat { Spacing.s8 }
    /// 标题上提 1：打包的 Noto Sans SC 行框上高下低 (ascent 1.16 em、descent 0.29 em)，17 号汉字的墨迹中心比行框中心低约 1，
    /// 上提后与返回箭头的墨迹中心、红绿灯中心 (y 26) 在一条线上。只挪画的位置，不改排版，横向位置不变。
    private static var titleLift: CGFloat { 1 }

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
            .offset(y: -Self.titleLift)
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
