import SwiftUI
import WageCore

// 桌面悬浮小牛的画面 (设计稿「发薪日倒计时 · 方案 C 桌面悬浮小牛」QB602)：
// 展开时是头顶气泡 + 脚边存钱罐 + 全身小牛 (`FloatingCowFigure`)，贴边收起时是白色小条 + 探头 (`FloatingCowPeek`)。
// 内容全部取自快照的 `FloatingCow`，这里只管画。App 固定浅色外观 (ADR-0004)，气泡与小条都是实底，深色桌面上照样看得清。

/// 展开的小牛连同四周留白 (发薪当天的彩带、气泡投影画在留白里)，大小固定为 `FloatingCowMetrics.canvas`，小牛靠右下。
/// 小牛按 `act` 做动作 (`CowRig`)，发薪当天和跳跃插播时周围撒彩带，气泡和存钱罐不动。
/// `act` 默认是快照给的姿势；`time` 只给离屏预览用，停在动画第几秒。系统开了「减弱动态效果」时停在静止姿势。
struct FloatingCowCanvas: View {
    let cow: FloatingCow
    var act: CowAct?
    var time: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let motion = time.map { CowMotion.frozen($0) } ?? (reduceMotion ? .rest : .live)
        let act = act ?? .pose(cow.pose)
        FloatingCowFigure(cow: cow, act: act, motion: motion)
            .overlay(alignment: .topLeading) {
                if act == .pose(.paid) { Confetti(motion: motion) }
            }
            .padding(FloatingCowMetrics.figureInsets)
            .frame(width: FloatingCowMetrics.canvas.width, height: FloatingCowMetrics.canvas.height, alignment: .bottomTrailing)
    }
}

/// 设计稿 Pet：气泡、指向小牛的尖角、脚边一排 (存钱罐 + 小牛)，右对齐，宽 164。
struct FloatingCowFigure: View {
    let cow: FloatingCow
    let act: CowAct
    let motion: CowMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Bubble(bubble: cow.bubble)
            BubbleTail()
                .fill(bubbleFill(cow.bubble.style))
                .frame(width: 16, height: 10)
                .padding(.trailing, 48)
            HStack(alignment: .bottom, spacing: 0) {
                if let jar = cow.jar { CoinJarView(jar: jar) }
                // 换动作时换一个新视图 (实时播放的图层重新搭)，淡入淡出。
                FloatingCowBody(act: act, motion: motion)
                    .id(act)
                    .transition(.opacity)
                    .frame(width: FloatingCowMetrics.cowSize.width, height: FloatingCowMetrics.cowSize.height)
            }
        }
        .frame(width: FloatingCowMetrics.figureWidth, alignment: .trailing)
        .animation(.easeInOut(duration: 0.25), value: act)
    }
}

/// 头顶气泡：小字前缀、大字 (数字用等宽字体，可带「天」)、一句台词。发薪当天 money 绿底白字。
private struct Bubble: View {
    let bubble: FloatingCowBubble

    var body: some View {
        let payday = bubble.style == .payday
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(bubble.prefix)
                .font(AppFont.ui(11, .medium))
                .foregroundStyle(payday ? Color.white.opacity(0.8) : Palette.muted)
            HStack(alignment: .bottom, spacing: Spacing.s4) {
                // 金额可能较长 (¥12,345.67)，放不下时整体缩小，不换行。
                Text(bubble.value)
                    .font(bubble.numeric ? AppFont.num(30, .extraBold) : AppFont.ui(26, .extraBold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit = bubble.unit {
                    Text(unit).font(AppFont.ui(13, .bold)).padding(.bottom, Spacing.s5)
                }
            }
            .foregroundStyle(valueColor(bubble.style))
            Text(bubble.quip)
                .font(AppFont.ui(12))
                .lineSpacing(12 * 0.4 / 2)
                .foregroundStyle(payday ? Color.white : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
        .frame(width: FloatingCowMetrics.figureWidth)
        .background(bubbleFill(bubble.style), in: RoundedRectangle(cornerRadius: Radius.r14))
        .shadow(color: Palette.ink.opacity(0.15), radius: 9, y: 6)
    }
}

/// 气泡下沿的尖角 (设计稿 path `M0 0 L16 0 L11 10 Z`)，尖头偏右，指向小牛的头。
private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 11 / 16, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private func bubbleFill(_ style: FloatingCowStyle) -> Color {
    style == .payday ? Palette.money : Palette.card
}

/// 大字 (气泡里的天数、小条上的天数) 的颜色。
private func valueColor(_ style: FloatingCowStyle) -> Color {
    switch style {
    case .ink: Palette.ink
    case .accent: Palette.accent
    case .payday: Palette.card
    }
}

/// 贴边收起的样子：白色小条「N 天 / 距发薪」+ 探头。探头图的右边框就是屏幕边缘，贴左边时整张图水平翻转，小条换到右边。
/// 探头也在动 (`CowRigs.peek`)；`time` 只给离屏预览用。
struct FloatingCowPeek: View {
    let pill: FloatingCowPill
    let side: FloatingCowEdge
    var time: TimeInterval?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.s4) {
            if side == .left { peek }
            Pill(pill: pill)
            if side == .right { peek }
        }
        .padding(.vertical, FloatingCowMetrics.peekPadding)
        .padding(side == .right ? .leading : .trailing, FloatingCowMetrics.peekPadding)
    }

    private var peek: some View {
        RigView(rig: CowRigs.peek, motion: time.map { CowMotion.frozen($0) } ?? (reduceMotion ? .rest : .live))
            .frame(width: FloatingCowMetrics.peekSize.width, height: FloatingCowMetrics.peekSize.height)
            .scaleEffect(x: side == .left ? -1 : 1, y: 1)
    }
}

/// 设计稿 Edge Peek 里的 Pill：白底圆角 14，上行大字 (15/800，数字用等宽)，下行 10/500 muted。
private struct Pill: View {
    let pill: FloatingCowPill

    var body: some View {
        VStack(spacing: 0) {
            Text(pill.value)
                .font(pill.value.contains(where: \.isNumber) ? AppFont.num(15, .extraBold) : AppFont.ui(15, .extraBold))
                .foregroundStyle(pill.style == .payday ? Palette.money : valueColor(pill.style))
            Text(pill.caption)
                .font(AppFont.ui(10, .medium))
                .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, Spacing.s6)
        .padding(.horizontal, Spacing.s10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.r14))
        .shadow(color: Palette.ink.opacity(0.15), radius: 6, y: 4)
    }
}

/// 设计稿 Jar：黑色盖子 + 金色投币口，半透明玻璃罐身里按层交错堆硬币 (3、2、3、2、3 枚)，左上一道高光；
/// 发薪当天罐口再冒出 3 枚。
struct CoinJarView: View {
    let jar: CoinJar

    /// 每层硬币的左上角 (罐身坐标，从底往上)，取自设计稿。
    private static let rows: [[CGPoint]] = [
        [CGPoint(x: 2, y: 34), CGPoint(x: 14.5, y: 34), CGPoint(x: 27, y: 34)],
        [CGPoint(x: 7, y: 25), CGPoint(x: 20, y: 25)],
        [CGPoint(x: 2, y: 16), CGPoint(x: 14.5, y: 16), CGPoint(x: 27, y: 16)],
        [CGPoint(x: 7, y: 7), CGPoint(x: 20, y: 7)],
        [CGPoint(x: 2, y: -2), CGPoint(x: 14.5, y: -2), CGPoint(x: 27, y: -2)],
    ]
    /// 发薪当天冒出罐口的 3 枚 (罐口上方 14 高的一条里)。
    private static let overflow = [CGPoint(x: 6, y: 2), CGPoint(x: 17, y: -1), CGPoint(x: 26, y: 3)]

    var body: some View {
        VStack(spacing: 0) {
            if jar.overflowing {
                coins(Self.overflow).frame(width: 40, height: 14, alignment: .topLeading)
            }
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 1, bottomTrailingRadius: 1, topTrailingRadius: 3)
                .fill(Palette.ink)
                .frame(width: 30, height: 7)
                .overlay(RoundedRectangle(cornerRadius: 1).fill(Palette.coin).frame(width: 12, height: 2))
            body(shape: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 13, bottomTrailingRadius: 13, topTrailingRadius: 6))
        }
        .padding(.bottom, Spacing.s4)
        .accessibilityElement()
        .accessibilityLabel("存钱罐")
    }

    private func body(shape: UnevenRoundedRectangle) -> some View {
        ZStack(alignment: .topLeading) {
            shape.fill(Palette.card.opacity(0.6))
            coins(Array(Self.rows.prefix(jar.rows).joined()))
            RoundedRectangle(cornerRadius: Radius.r2)
                .fill(Palette.card.opacity(0.7))
                .frame(width: 3, height: 30)
                .offset(x: 6, y: 6)
        }
        .frame(width: 40, height: 50)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.muted, lineWidth: 1.5))
    }

    private func coins(_ points: [CGPoint]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(points.indices, id: \.self) { index in
                Coin().offset(x: points[index].x, y: points[index].y)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 12×12 的一枚硬币：金色面、深色描边、内圈。
private struct Coin: View {
    var body: some View {
        Circle()
            .fill(Palette.coin)
            .overlay(Circle().strokeBorder(Palette.coinEdge, lineWidth: 1))
            .overlay(Circle().strokeBorder(Palette.coinRing, lineWidth: 1).frame(width: 6, height: 6))
            .frame(width: 12, height: 12)
    }
}

/// 贴在屏幕哪一边。
enum FloatingCowEdge: String, Codable {
    case left
    case right
}

/// 浮窗的尺寸：窗口大小由这里决定，视图按它排版。
enum FloatingCowMetrics {
    /// 设计稿 Pet 宽 164 (气泡宽)。
    static let figureWidth: CGFloat = 164
    /// 全身小牛 120×160。
    static let cowSize = CGSize(width: 120, height: 160)
    /// 探头图 80×100。
    static let peekSize = CGSize(width: 80, height: 100)
    /// 展开时小牛四周的留白：左上给彩带，右边给气泡投影。点在留白 (透明处) 上会穿透到下面的窗口。
    static let figureInsets = EdgeInsets(top: 44, leading: 44, bottom: 4, trailing: 16)
    /// 展开的浮窗大小：气泡最多两行台词也放得下，小牛贴右下角。
    static let canvas = CGSize(width: figureInsets.leading + figureWidth + figureInsets.trailing, height: 340)
    /// 收起时小条与探头四周 (贴边那一侧除外) 留给投影的空白；收起的浮窗大小按内容量 (小条宽随天数变)。
    static let peekPadding: CGFloat = 12
}
