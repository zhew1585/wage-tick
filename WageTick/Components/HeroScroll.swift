import SwiftUI

/// 头图 + 下面的内容一起放进滚动区：内容放不下时往下滑，头图从 320 收成 100 高的窄栏并钉在顶上，内容从它下面滑过。
/// 头图也在滚动区里，鼠标停在头图上滚动一样有效；内容放得下时整个滚动区锁住，连一两个点也滑不动，头图保持完整。
/// 不显示滚动条，能滑就行。
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

    /// 内容 (含头图) 的高度与可见区域的高度，用来判断要不要滚动。
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

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
            .background(HiddenScrollers())
            .background(GeometryReader { Color.clear.preference(key: HeroScrollContentHeight.self, value: $0.size.height) })
        }
        .background(GeometryReader { Color.clear.preference(key: HeroScrollViewportHeight.self, value: $0.size.height) })
        .onPreferenceChange(HeroScrollContentHeight.self) { contentHeight = $0 }
        .onPreferenceChange(HeroScrollViewportHeight.self) { viewportHeight = $0 }
        // 放得下 (算上不到 1pt 的取整误差) 就不让滚：不然多出的零点几个点也能拖动，看着像能滑但什么都没有。
        .scrollDisabled(contentHeight <= viewportHeight + 1)
        .coordinateSpace(name: Self.space)
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct HeroScrollContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct HeroScrollViewportHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
