import SwiftUI

/// 大胆版头图 (设计稿「大胆风格」)：铺满状态色的渐变大块，下沿大圆角，内容顶到窗口上沿 (红绿灯画在它上面)。
/// 从上到下：标题栏一行 (红绿灯右边的返回胶囊、右侧日期或状态)、站酷体标题、大数字 (由调用方给)、一行说明；
/// 右下角站着小牛 (随场景换动作)，头顶一个白色气泡。所有页面头图统一 `BoldHero.height` 高；
/// 往下滑时收成 `BoldHero.collapsedHeight` 高的窄栏 (`collapse` 从 0 到 1)，只留返回、标题与小号数字，小牛只露头。
///
/// 用法：
/// ```
/// BoldHero(theme: .orange, kicker: "今日已赚", caption: "满勤日薪 ¥1000") {
///     HeroAmount(headline: "¥571.4286", theme: .orange)
/// }
/// ```
/// 子页面传 `back`，首页传 `topLeading` / `topTrailing` 放日期与状态胶囊。
struct BoldHero<Number: View>: View {

    let theme: HeroTheme
    var back: HeroBack?
    /// 标题栏一行右侧的小字 (如表单的日期)。
    var titlebarTrailing: String?
    /// 标题上方一行：左边日期、右边状态胶囊 (首页)。
    var topLeading: String?
    var status: HeroStatus?
    let kicker: String
    var caption: String?
    var captionIcon: Phosphor?
    var cow: CowAct?
    var bubble: HeroBubbleContent?
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
            theme.gradient
            if confetti { ConfettiField().opacity(fullOpacity) }
            full.opacity(fullOpacity)
            compact.opacity(compactOpacity)
            titlebar
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius))
        .shadow(color: collapse > 0.95 ? theme.bottom.opacity(0.25) : .clear, radius: 8, y: 4)
    }

    private var radius: CGFloat { 32 - 8 * collapse }
    private var fullOpacity: Double { Double(1 - min(1, collapse * 1.6)) }
    private var compactOpacity: Double { Double(max(0, collapse * 1.6 - 0.6)) }

    /// 标题栏一行：与系统红绿灯同一行 (标题栏 28 高)，返回胶囊在红绿灯右边，右侧小字靠右。
    private var titlebar: some View {
        HStack(spacing: 0) {
            if let back {
                HeroBackButton(back: back, theme: theme)
            }
            Spacer(minLength: 0)
            if let titlebarTrailing {
                Text(titlebarTrailing).font(AppFont.num(12)).foregroundStyle(theme.secondary)
            }
        }
        .padding(.leading, WindowChrome.Titlebar.standard.leadingInset - Spacing.s4)
        .padding(.trailing, Spacing.screen)
        .frame(height: WindowChrome.Titlebar.standard.height)
    }

    /// 完整头图：标题栏下面是日期与状态、标题、数字、说明；小牛与气泡贴右下角。
    private var full: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                if topLeading != nil || status != nil {
                    HStack {
                        if let topLeading {
                            Text(topLeading).font(AppFont.num(12)).foregroundStyle(theme.secondary).monospacedDigit()
                        }
                        Spacer(minLength: 0)
                        if let status { HeroStatusPill(status: status) }
                    }
                    .padding(.bottom, Spacing.s4)
                } else {
                    Spacer().frame(height: Spacing.s16)
                }
                Text(kicker)
                    .font(AppFont.fun(26))
                    .foregroundStyle(theme.kicker)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: cow == nil ? .infinity : 240, alignment: .leading)
                number()
                    .padding(.top, Spacing.s4)
                if let caption {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                        if let captionIcon { PhosphorIcon(captionIcon, size: 13).iconOnTextBaseline() }
                        Text(caption).font(AppFont.num(12, .bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(theme.kicker)
                    .frame(maxWidth: cow == nil ? .infinity : 190, alignment: .leading)
                    .padding(.top, Spacing.s14)
                }
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: WindowChrome.Titlebar.standard.height + Spacing.s8, leading: Spacing.screen, bottom: 0, trailing: Spacing.screen))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let cow {
                HeroCow(act: cow, bubble: bubble, theme: theme)
            }
        }
    }

    /// 窄栏：标题栏下面一行小号数字与标题，小牛只露头。
    private var compact: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: Spacing.s8) {
                if let compactValue {
                    Text(compactValue).font(AppFont.heavy(34)).foregroundStyle(theme.number).lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(kicker).font(AppFont.fun(20)).foregroundStyle(theme.kicker).lineLimit(1)
            }
            .padding(.leading, Spacing.screen)
            .padding(.top, WindowChrome.Titlebar.standard.height + Spacing.s8)
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

/// 返回胶囊：箭头 + 文字，半透明底，放在红绿灯右边 (返回即关窗或回到上一页)。
struct HeroBack {
    let label: String
    let action: () -> Void
}

/// 首页右上角的状态胶囊：墨色底、白字，前面一个亮色圆点。
struct HeroStatus: Equatable {
    let label: String
    let dot: Color
    var fill: Color = Palette.ink
}

/// 小牛头顶气泡的内容：小字前缀 + 大字 (倒计时、金额)，或者只有一句话 (台词)。
struct HeroBubbleContent: Equatable {
    var prefix: String?
    let value: String
    /// 大字用数字字体 (倒计时、金额) 还是站酷体 (一句话)。
    var numeric: Bool
}

private struct HeroBackButton: View {
    let back: HeroBack
    let theme: HeroTheme

    var body: some View {
        Button(action: back.action) {
            HStack(spacing: Spacing.s2) {
                PhosphorIcon(.caretLeft, size: 13)
                Text(back.label).font(AppFont.ui(12, .bold))
            }
            .foregroundStyle(theme.onChip)
            .padding(EdgeInsets(top: 3, leading: Spacing.s6, bottom: 3, trailing: Spacing.s10))
            .background(theme.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityLabel("返回\(back.label)")
    }
}

struct HeroStatusPill: View {
    let status: HeroStatus

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Circle().fill(status.dot).frame(width: 7, height: 7)
            Text(status.label).font(AppFont.ui(12, .bold)).foregroundStyle(.white)
        }
        .padding(.horizontal, Spacing.s10)
        .padding(.vertical, 5)
        .background(status.fill, in: Capsule())
    }
}

/// 右下角的小牛与头顶气泡：小牛 160×213 站在头图底边上 (脚被下沿裁掉一截)，气泡在头顶偏左。
private struct HeroCow: View {
    let act: CowAct
    let bubble: HeroBubbleContent?
    let theme: HeroTheme

    var body: some View {
        FloatingCowBody(act: act, motion: .live)
            .frame(width: 160, height: 213)
            .offset(x: 4, y: act == .pose(.lyingFlat) ? -4 : 26)
            .overlay(alignment: .topTrailing) {
                if let bubble {
                    HeroBubble(content: bubble, accent: theme.bubbleAccent)
                        .frame(maxWidth: bubble.numeric ? 150 : 124, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: -6, y: act == .pose(.lyingFlat) ? 30 : -30)
                }
            }
            .allowsHitTesting(false)
    }
}

/// 白色气泡：左下角是尖角，有一层淡投影。
struct HeroBubble: View {
    let content: HeroBubbleContent
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let prefix = content.prefix {
                Text(prefix).font(AppFont.ui(10)).foregroundStyle(Palette.muted)
            }
            Text(content.value)
                .font(content.numeric ? AppFont.heavy(20) : AppFont.fun(16))
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s6)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 4, bottomTrailingRadius: 14, topTrailingRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 4)
    }
}

/// 发薪日头图上的彩纸：几片固定位置的小方块，避开文字区。
private struct ConfettiField: View {
    private static let pieces: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color, angle: Double)] = [
        (200, 18, 10, 18, Palette.highlight, 20), (320, 20, 8, 14, .white, -30), (238, 216, 7, 7, .white, 0),
        (344, 198, 10, 16, Palette.highlight, 45), (150, 22, 6, 12, Palette.ink, 15), (214, 264, 9, 15, .white, 60),
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
