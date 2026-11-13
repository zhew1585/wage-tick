import SwiftUI

/// 头图 + 下面的内容一起放进滚动区：内容放不下时往下滑，头图从 320 收成 100 高的窄栏并钉在顶上，内容从它下面滑过。
/// 头图也在滚动区里，鼠标停在头图上滚动一样有效；内容放得下时不滚动，头图保持完整。
/// 底部固定的按钮栏不放进来，放在它下面 (`VStack { HeroScroll {…} content: {…}; 底部按钮栏 }`)。
///
/// 用法：
/// ```
/// HeroScroll { collapse in
///     BoldHero(theme: .orange, kicker: "目标", collapse: collapse) { … }
/// } content: {
///     列表
/// }
/// ```
struct HeroScroll<Hero: View, Content: View>: View {
    @ViewBuilder let hero: (CGFloat) -> Hero
    @ViewBuilder let content: () -> Content

    private static var space: String { "HeroScroll" }

    var body: some View {
        let range = HeroMetrics.height - HeroMetrics.collapsedHeight
        ScrollView {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    let scrolled = max(0, -geometry.frame(in: .named(Self.space)).minY)
                    let collapse = min(scrolled / range, 1)
                    hero(collapse)
                        .frame(height: HeroMetrics.height - range * collapse, alignment: .top)
                        .offset(y: scrolled)
                }
                .frame(height: HeroMetrics.height)
                .zIndex(1)
                content()
            }
            .background(OverlayScrollers())
        }
        .coordinateSpace(name: Self.space)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
