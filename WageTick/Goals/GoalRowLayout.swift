import SwiftUI

/// 目标页一行的三行结构，累计中、排队中、已完成共用：行宽 320、行高 76，左边距 14 放图标，图标右边 10 起是内容区，右边距 14。
/// - 第一行 (高 20)：名称一栏占满金额左边剩下的全部宽度，与金额间距 8；金额先于名称排版，名称至少留 `nameMinWidth`。
/// - 第二行 (高 6)：整宽进度条，只是装饰，读屏不念。
/// - 第三行 (高 16)：小字说明，悬停时右端出按钮 (各 16、间距 6，右沿与金额右沿对齐)。
/// 按钮只放在第三行，第一行没有按钮，名称一栏悬停前后宽度完全一样；第三行高度固定、小字靠左，按钮出现、消失时小字和行高都不动。
struct GoalRowLayout<Icon: View, Name: View, Amount: View, Caption: View, Buttons: View>: View {
    /// 名称一栏至少留多宽：只有上限出现之前存下的超大金额才会挤到这里，此时金额截断，名称仍露出开头几个字。
    let nameMinWidth: CGFloat
    let track: GoalTrack
    @ViewBuilder let icon: Icon
    @ViewBuilder let name: Name
    @ViewBuilder let amount: Amount
    @ViewBuilder let caption: Caption
    @ViewBuilder let buttons: Buttons

    var body: some View {
        HStack(spacing: Spacing.s10) {
            icon
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack(spacing: Spacing.s8) {
                    name.frame(minWidth: nameMinWidth, maxWidth: .infinity, alignment: .leading)
                    amount.lineLimit(1).layoutPriority(1)
                }
                .frame(height: 20)
                track.frame(height: 6).accessibilityHidden(true)
                HStack(spacing: Spacing.s6) {
                    caption.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    buttons
                }
                .frame(height: 16)
            }
        }
        .padding(.horizontal, Spacing.s14)
        .frame(height: GoalRowMetrics.height)
    }
}

enum GoalRowMetrics {
    /// 目标行的固定行高，攒钱队列拖动排序按它算落点。
    static let height: CGFloat = 76
}

/// 目标行的进度条：圆角整条底色，按进度从左填充；不填充时只有底色 (排队中的空条、已完成的满条都只画底色)。
struct GoalTrack: View {
    let base: Color
    var fill: Color = .clear
    var progress: Double = 0

    var body: some View {
        Capsule()
            .fill(base)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
    }
}
