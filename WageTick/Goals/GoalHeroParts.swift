import AppKit
import SwiftUI

/// 目标窗口头图里的大数字：Archivo Black 白色计数 + 站酷体墨色单位，如「4 个在排队」「7 件到手」(设计稿「目标-攒钱队列」「目标-已到手」)。
/// 单位固定墨色 (不跟头图标题色走)：绿色头图的标题是黄的，单位仍是墨色。
///
/// 用法：`BoldHero(…) { HeroCount(value: "4", unit: "个在排队", theme: .orange) }`
struct HeroCount: View {
    let value: String
    let unit: String
    let theme: HeroTheme

    private static let size: CGFloat = 120

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.s10) {
            Text(value)
                .font(AppFont.heavy(Self.size))
                .tracking(-Self.size * 0.04)
                .foregroundStyle(theme.number)
            Text(unit).font(AppFont.fun(Self.size * 0.3)).foregroundStyle(Palette.ink)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: 250, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value + unit)
    }
}

/// 头图里的墨色说明行 (图标 + 等宽粗体小字)，放在大数字下面。
/// `BoldHero` 的说明行跟标题同色，绿色头图上是黄的；已到手页设计稿的说明行是墨色，所以自己画在数字闭包里。
struct HeroInkCaption: View {
    let icon: ImageResource
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            PhosphorIcon(icon, size: 13).iconOnTextBaseline()
            Text(text).font(AppFont.num(12, .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.ink)
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

/// 头图里的金额输入框用黄色光标 (橙色底上看得见)，离开时换回主题色。
/// 光标颜色在窗口共用的字段编辑器上 (见 `FieldEditorTheme`)，这里在输入框获得焦点时改它。
@MainActor
enum FieldCaret {
    static func set(_ color: Color) {
        guard let editor = NSApp.keyWindow?.fieldEditor(false, for: nil) as? NSTextView else { return }
        editor.insertionPointColor = NSColor(color)
    }
}
