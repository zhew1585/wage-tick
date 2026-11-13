import SwiftUI

/// 大胆版表单外框 (设计稿「弹窗-今天扣钱了」「弹窗-请假」)：顶部 320 高的彩色头图 (调用方给 `BoldHero`，返回胶囊在红绿灯右边)，
/// 下面是内容 (左右 20、组间距 18)，底部按钮行固定在窗口底部 (胶囊按钮、间距 10)。
/// 头图与内容一起放进 `HeroScroll`：放不下时往下滑，头图收成窄栏钉在顶上。
/// 宽 360，与今日概览面板同宽：在面板里原地替换面板内容 (占满窗口)，在历史单日详情里作为 sheet 弹出 (按内容高度)。
///
/// 用法：`FormSheet { collapse in BoldHero(…, collapse: collapse) { … } } content: { 内容 } actions: { 按钮 }`
struct FormSheet<Hero: View, Content: View, Actions: View>: View {
    @ViewBuilder let hero: (CGFloat) -> Hero
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            HeroScroll(hero: hero) {
                VStack(alignment: .leading, spacing: Spacing.s18) {
                    content()
                }
                .padding(EdgeInsets(top: Spacing.s20, leading: Spacing.screen, bottom: Spacing.s16, trailing: Spacing.screen))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Spacing.s10) {
                actions()
            }
            .padding(EdgeInsets(top: Spacing.s12, leading: Spacing.screen, bottom: Spacing.s20, trailing: Spacing.screen))
        }
        .frame(width: PanelMetrics.width)
        .background(Palette.bg)
    }
}

/// 表单里的小标题 (13/700 墨色)，如「为啥被扣 (可不选)」「请哪段」。
struct FormLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).font(AppFont.ui(13, .bold)).foregroundStyle(Palette.ink)
    }
}

/// 一组标题 + 控件，间距 8。
struct FormGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            FormLabel(title)
            content()
        }
    }
}

/// 表单底部左边的「算了」：墨色描边胶囊，固定宽 108；按 Esc 也是它。
struct FormCancelButton: View {
    var title = "算了"
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.pill(.outline))
            .frame(width: 108)
    }
}
