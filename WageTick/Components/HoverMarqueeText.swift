import SwiftUI

/// 单行文字，放不下时尾部省略；`isActive` (如鼠标悬停在所在的行上) 且此刻放不下时在原位横向滚动露出全文。
/// 滚动节奏：开头停 0.8 秒，以每秒 30 pt 向左滚到末尾露全，停 0.8 秒，回到开头，循环；滚动时两端裁掉，不出省略号。
/// `isActive` 变为 false 立刻回到静止的省略样子；系统开了「减弱动态效果」时不滚动。放不下时 `.help` 给出全文。
/// 占满给它的宽度 (文字靠左)，滚动的可见区域就是这一整栏，滚到末尾时文字右端贴着这一栏的右沿；
/// 静止的那份文字始终参与排版，滚动的那份只是叠在上面，滚不滚占的宽度都一样。
/// 字体、颜色从外面设，如 `HoverMarqueeText(name, isActive: hovering).font(…).foregroundStyle(…)`。
/// 不滚动时没有任何定时任务：滚动用 `KeyframeAnimator`，只在滚动时挂在视图上，停下即移除。
struct HoverMarqueeText: View {
    let text: String
    let isActive: Bool

    init(_ text: String, isActive: Bool) {
        self.text = text
        self.isActive = isActive
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 文字不受限时的自然宽度。
    @State private var fullWidth: CGFloat = 0
    /// 这一栏的宽度。
    @State private var shownWidth: CGFloat = 0

    /// 开头、结尾各停多久 (秒)。
    private static let hold = 0.8
    /// 滚动速度 (pt/秒)。
    private static let speed: CGFloat = 30

    /// 放不下时要滚动的距离；放得下为 0。小于 0.5 pt 的差视为放得下，免得量宽度的舍入误差触发滚动。
    private var overflow: CGFloat {
        let gap = fullWidth - shownWidth
        return gap > 0.5 ? gap : 0
    }

    private var scrolls: Bool { isActive && !reduceMotion && overflow > 0 }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(scrolls ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { widthReader { shownWidth = $0 } }
            .background(alignment: .leading) {
                Text(text).lineLimit(1).fixedSize().hidden()
                    .background { widthReader { fullWidth = $0 } }
            }
            .overlay(alignment: .leading) {
                if scrolls { marquee.id(overflow) }
            }
            .help(overflow > 0 ? text : "")
    }

    /// 滚动的那份文字：按自然宽度排开，裁在这一栏里。
    private var marquee: some View {
        let distance = overflow
        return Text(text)
            .lineLimit(1)
            .fixedSize()
            .keyframeAnimator(initialValue: CGFloat(0), repeating: true) { content, offset in
                content.offset(x: -offset)
            } keyframes: { _ in
                LinearKeyframe(0, duration: Self.hold)
                LinearKeyframe(distance, duration: distance / Self.speed)
                LinearKeyframe(distance, duration: Self.hold)
            }
            // minWidth 0：外框取这一栏的宽度，不被更宽的滚动文字撑开，裁切才落在原位。
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }

    /// 量所在视图的宽度，出现和变化时回报。
    private func widthReader(_ report: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { report(geometry.size.width) }
                .onChange(of: geometry.size.width) { _, width in report(width) }
        }
    }
}
