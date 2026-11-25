import SwiftUI

/// 各页面顶部的头图。版面沿用大胆版 (所以还叫 `BoldHero`)，外观是经典版 (同 nightly.20261112.15)：
/// 米白平底、下沿一条分隔线，内容顶到窗口上沿 (红绿灯画在它上面)，状态色只用在状态文字与气泡大字上 (`HeroTheme.classic`)。
/// 从上到下：标题栏一行 (红绿灯右边的返回、右侧日期)、日期与状态、标题 17/700、大数字 (由调用方给)、一行说明；
/// 右下角站着小牛 (随场景换动作)，头顶一个白色气泡。所有页面头图统一 `HeroMetrics.height` 高；
/// 往下滑时收成 `HeroMetrics.collapsedHeight` 高的窄栏 (`collapse` 从 0 到 1)，只留返回、标题与小号数字，小牛只露头。
///
/// 用法：
/// ```
/// BoldHero(theme: .orange, kicker: "今日已赚", caption: "满勤日薪 ¥1000") {
///     HeroAmount(text: "¥571.4286", theme: .orange)
/// }
/// ```
/// 子页面传 `back`，首页传 `topLeading`、`status` 放日期与日状态。
struct BoldHero<Number: View>: View {

    let theme: HeroTheme
    var back: HeroBack?
    /// 标题栏一行右侧的小字 (如表单的日期)。
    var titlebarTrailing: String?
    /// 标题栏右侧小字离右边的距离；今日概览右上角有钉住按钮，表单里要让开它。
    var titlebarTrailingInset: CGFloat = Spacing.screen
    /// 标题上方一行：左边日期、右边状态胶囊 (首页)。
    var topLeading: String?
    var status: HeroStatus?
    let kicker: String
    var caption: String?
    var captionIcon: Phosphor?
    var cow: CowAct?
    var bubble: HeroBubbleContent?
    /// 气泡相对小牛头顶右侧的位置；nil 时按默认 (倒计时在头顶上方，台词贴着耳朵)。
    /// 头图左边放了很宽的内容 (如引导页的大号输入) 时，挪到小牛左边、说明行下面。
    var bubbleOffset: CGSize?
    /// 发薪日在头图上撒几片彩纸。
    var confetti = false
    /// 收起程度：0 为完整头图，1 为窄栏。
    var collapse: CGFloat = 0
    /// 收起后窄栏里的小号数字 (如「4」「¥571」)，nil 时只留标题。
    var compactValue: String?
    @ViewBuilder let number: () -> Number

    var body: some View {
        let height: CGFloat = HeroMetrics.height - (HeroMetrics.height - HeroMetrics.collapsedHeight) * collapse
        ZStack(alignment: .topLeading) {
            Palette.bg
            if confetti { ConfettiField().opacity(fullOpacity) }
            full.opacity(fullOpacity)
            compact.opacity(compactOpacity)
            titlebar
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    /// 经典配色，头图里只用它的颜色。
    private var style: HeroTheme { theme.classic }
    private var fullOpacity: Double { Double(1 - min(1, collapse * 1.6)) }
    private var compactOpacity: Double { Double(max(0, collapse * 1.6 - 0.6)) }

    /// 标题栏一行：与系统红绿灯同一行，返回在红绿灯右边，右侧小字靠右。
    private var titlebar: some View {
        HStack(spacing: 0) {
            if let back {
                HeroBackButton(back: back)
            }
            Spacer(minLength: 0)
            if let titlebarTrailing {
                Text(titlebarTrailing).font(AppFont.body).foregroundStyle(style.secondary)
            }
        }
        .padding(.leading, WindowChrome.Titlebar.hero.leadingInset - Spacing.s4)
        .padding(.trailing, titlebarTrailingInset)
        .frame(height: WindowChrome.Titlebar.hero.height)
    }

    /// 完整头图：标题栏下面是日期与状态、标题、数字、说明；小牛与气泡贴右下角。
    private var full: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                if topLeading != nil || status != nil {
                    HStack {
                        if let topLeading {
                            Text(topLeading).font(AppFont.label).foregroundStyle(style.secondary).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        if let status { HeroStatusPill(status: status, tone: style.bubbleAccent) }
                    }
                    .padding(.bottom, Spacing.s12)
                } else {
                    Spacer().frame(height: Spacing.s16)
                }
                // 标题在小牛头顶上方，占满整行；行高固定，太长缩小字号时下面的内容也不会上下跳。
                Text(kicker)
                    .font(AppFont.pageTitle)
                    .foregroundStyle(style.kicker)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
                number()
                    .padding(.top, Spacing.s6)
                if let caption {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                        if let captionIcon { PhosphorIcon(captionIcon, size: 13).iconOnTextBaseline() }
                        // 放不下时只在「 · 」处换行，每段 (如「时薪 ¥119.05」) 不拆开。
                        SegmentedText(BoldNumber.groupedAll(caption)).font(AppFont.caption)
                    }
                    .foregroundStyle(style.secondary)
                    // 小牛从 x≈200 起，说明行限宽 180 不钻到小牛后面，放不下折成两行。
                    .frame(maxWidth: cow == nil ? .infinity : 180, alignment: .leading)
                    .padding(.top, Spacing.s14)
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: WindowChrome.Titlebar.hero.height + Spacing.s8, leading: Spacing.screen, bottom: 0, trailing: Spacing.screen))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let cow {
                HeroCow(act: cow, bubble: bubble, bubbleOffset: bubbleOffset, accent: style.bubbleAccent)
            }
        }
    }

    /// 窄栏：标题栏下面一行小号数字与标题，小牛只露头。
    private var compact: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: Spacing.s8) {
                if let compactValue {
                    Text(BoldNumber.grouped(compactValue)).font(AppFont.num(24, .bold)).foregroundStyle(style.number).lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(kicker).font(AppFont.section).foregroundStyle(style.kicker).lineLimit(1)
            }
            .padding(.leading, Spacing.screen)
            .padding(.top, WindowChrome.Titlebar.hero.height + Spacing.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let cow {
                FloatingCowBody(act: cow, motion: .rest)
                    .frame(width: 100, height: 133)
                    .padding(.top, Spacing.s20)
                    .padding(.trailing, Spacing.s8)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// 返回：箭头 + 文字，放在红绿灯右边，回到上一页。
struct HeroBack {
    let label: String
    let action: () -> Void
}

/// 首页右上角的日状态。经典版只画圆点 + 文字，按状态着色：`fill` 不是默认的墨色时用它 (白干中)，否则用头图的强调色；`dot` 不再使用。
struct HeroStatus: Equatable {
    let label: String
    let dot: Color
    var fill: Color = Palette.ink
}

/// 小牛头顶气泡的内容：小字前缀 + 大字 (倒计时、金额)，或者只有一句话 (台词)。
struct HeroBubbleContent: Equatable {
    var prefix: String?
    let value: String
    /// 大字用数字字体 (倒计时、金额) 还是界面字体 (一句话)。
    var numeric: Bool
}

/// 箭头 14 + 文字 13/500，墨色；悬停、按下时外扩一圈圆角底 (同经典版页头的返回)。
private struct HeroBackButton: View {
    let back: HeroBack

    var body: some View {
        Button(action: back.action) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                PhosphorIcon(.caretLeft, size: 14).iconOnTextBaseline(13)
                Text(back.label).font(AppFont.bodyMedium)
            }
            .foregroundStyle(Palette.ink)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: Radius.r6, outset: Spacing.s4))
        .accessibilityLabel("返回\(back.label)")
    }
}

/// 日状态：圆点 8 + 文字 17/700，按状态着色，无底色 (经典版面板顶部的样子)。
struct HeroStatusPill: View {
    let status: HeroStatus
    /// 头图的强调色；`status.fill` 是默认墨色时用它。
    let tone: Color

    var body: some View {
        let color = status.fill == Palette.ink ? tone : status.fill
        HStack(spacing: Spacing.s6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(status.label).font(AppFont.pageTitle).foregroundStyle(color)
        }
    }
}

/// 右下角的小牛与头顶气泡：小牛 160×213 站在头图底边上 (脚被下沿裁掉一截)，气泡在头顶偏左。
private struct HeroCow: View {
    let act: CowAct
    let bubble: HeroBubbleContent?
    let bubbleOffset: CGSize?
    /// 气泡里大字的颜色。
    let accent: Color

    var body: some View {
        FloatingCowBody(act: act, motion: .live)
            .frame(width: 160, height: 213)
            .offset(x: 4, y: act == .pose(.lyingFlat) ? -4 : 26)
            .overlay(alignment: .topTrailing) {
                if let bubble {
                    // 设计稿：两行的倒计时气泡在头顶上方，一行的台词贴着耳朵；躺平的小牛头低，气泡跟着往下。
                    // 台词最宽 150，长的折成两行，不压到左边的大数字。
                    // 气泡挪到小牛左边时，尖角改到右下，指向小牛。
                    HeroBubble(content: bubble, accent: accent, tailOnRight: (bubbleOffset?.width ?? 0) < -50)
                        .frame(maxWidth: bubble.numeric ? nil : 150, alignment: .trailing)
                        .fixedSize(horizontal: bubble.numeric, vertical: true)
                        .offset(bubbleOffset ?? CGSize(width: -6, height: act == .pose(.lyingFlat) ? 70 : (bubble.prefix == nil ? -6 : -30)))
                }
            }
            .allowsHitTesting(false)
    }
}

/// 白色气泡：1pt line 描边，左下角 (在小牛左边时右下角) 是尖角。
struct HeroBubble: View {
    let content: HeroBubbleContent
    let accent: Color
    /// 尖角在右下 (气泡在小牛左边时)；默认在左下。
    var tailOnRight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let prefix = content.prefix {
                Text(prefix).font(AppFont.ui(10)).foregroundStyle(Palette.muted)
            }
            Text(content.value)
                .font(content.numeric ? AppFont.numStat : AppFont.section)
                .foregroundStyle(content.numeric ? accent : Palette.ink)
                .monospacedDigit()
                .lineLimit(content.numeric ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s6)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Radius.r10, bottomLeadingRadius: tailOnRight ? Radius.r10 : Radius.r2,
            bottomTrailingRadius: tailOnRight ? Radius.r2 : Radius.r10, topTrailingRadius: Radius.r10
        )
    }
}

/// 发薪日头图上的彩纸：几片固定位置的小方块，避开文字区；颜色同经典版庆祝动画 (accent、money、loss、ink、line)。
private struct ConfettiField: View {
    private static let pieces: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color, angle: Double)] = [
        (200, 18, 10, 18, Palette.accent, 20), (320, 20, 8, 14, Palette.money, -30), (238, 216, 7, 7, Palette.line, 0),
        (344, 198, 10, 16, Palette.accent, 45), (150, 22, 6, 12, Palette.ink, 15), (214, 264, 9, 15, Palette.loss, 60),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.pieces.enumerated()), id: \.offset) { _, piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.w, height: piece.h)
                    .rotationEffect(.degrees(piece.angle))
                    .position(x: piece.x + piece.w / 2, y: piece.y + piece.h / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// 头图尺寸：所有页面统一 320 高，往下滑收成 100 高的窄栏。
enum HeroMetrics {
    static let height: CGFloat = 320
    static let collapsedHeight: CGFloat = 100
}
