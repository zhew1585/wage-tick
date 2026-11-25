import AppKit
import SwiftUI

/// 目标页头图里的大数字 (经典视觉，同头图主数字)：JetBrains Mono 54/700 墨色计数 + 26/600 muted 单位，如「4 个在排队」「7 件到手」。
///
/// 用法：`BoldHero(…) { HeroCount(value: "4", unit: "个在排队", theme: .orange) }`
struct HeroCount: View {
    let value: String
    let unit: String
    let theme: HeroTheme

    private static let size: CGFloat = 54

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.s6) {
            Text(value)
                .font(AppFont.num(Self.size, .bold))
                .tracking(-1.5)
                .foregroundStyle(theme.classic.number)
            Text(unit).font(AppFont.ui(26, .semibold)).foregroundStyle(Palette.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: 250, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value + unit)
    }
}

/// 头图里的说明行 (图标 + 12 muted，同 `BoldHero` 的说明行)，放在大数字下面；已到手页把它画在数字闭包里。
struct HeroInkCaption: View {
    let icon: ImageResource
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            PhosphorIcon(icon, size: 13).iconOnTextBaseline()
            SegmentedText(text).font(AppFont.caption)
        }
        .foregroundStyle(Palette.muted)
        .frame(maxWidth: 190, alignment: .leading)
        .padding(.top, Spacing.s14)
    }
}

/// `HeroScroll`，但内容只要放不下，就能一直往下滑到头图完全收成窄栏 (设计稿「目标-滑动后头图收起」)：
/// 内容只比窗口高一点时，`HeroScroll` 只能滑那一点，头图收不起来；这里把内容垫高到「窗口高 - 窄栏高」。放得下时不垫，不滚动。
struct CollapsingHeroScroll<Hero: View, Content: View>: View {
    @ViewBuilder let hero: (CGFloat) -> Hero
    @ViewBuilder let content: () -> Content

    @State private var viewport: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let overflows = viewport > 0 && contentHeight + HeroMetrics.height > viewport + 0.5
        HeroScroll(hero: hero) {
            content()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .frame(minHeight: overflows ? viewport - HeroMetrics.collapsedHeight : nil, alignment: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewport = $0 }
    }
}

/// 头图收起成窄栏时把标题换成单位 (设计稿「目标-滑动后头图收起」：窄栏写「4 个在排队」而不是「4 想要的都写下来」)。
/// 收到一半时换：此时完整头图已几乎透明，看不出标题在变。
func heroKicker(_ title: String, collapsed unit: String, collapse: CGFloat) -> String {
    collapse > 0.5 ? unit : title
}
