import SwiftUI
import WageCore

// 桌面小组件 (PRD F14，设计稿「macOS 桌面小组件」uRf1y) 各尺寸共用的零件。App 与小组件扩展两个 target 都编译，
// App 里只给离屏预览用 (`WidgetPreviews`)。文字、数字原样取自核心的 `WidgetSnapshot`，这里只管排版。

/// 小组件的三种尺寸 (不做超大号)。和 WidgetKit 的 `WidgetFamily` 分开，预览不必依赖 WidgetKit 环境。
enum WidgetSize: CaseIterable {
    case small
    case medium
    case large

    /// 设计稿里的尺寸 (pt)，预览按它排版；桌面上由系统决定。
    var designSize: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}

/// 状态色调对应的颜色，与面板顶部状态一致 (`PanelTopBar`)：应出勤日 money、休息日 accent、白干中 loss。
extension WidgetTone {
    var color: Color {
        switch self {
        case .attendance: Palette.money
        case .rest: Palette.accent
        case .unpaidWork: Palette.loss
        }
    }
}

/// 计时文字的走法：桌面上由系统实时走；离屏预览停在条目时刻 (`ImageRenderer` 画计时文字时按真实时间算，只能写死)。
struct WidgetClock {
    /// 这一条的时刻。
    let now: Date
    /// 为 true 时计时停在 `now`，画成固定的 h:mm:ss，只给预览用。
    var frozen = false

    /// 一项的值：文字原样，倒计时与正计时用系统计时文字 (h:mm:ss)。
    func text(_ value: WidgetValue) -> Text {
        switch value {
        case .text(let text):
            Text(text)
        case .countdown(let end):
            frozen ? Self.frozenText(end.timeIntervalSince(now)) : Text(timerInterval: min(now, end)...end, countsDown: true)
        case .elapsed(let since):
            frozen ? Self.frozenText(now.timeIntervalSince(since)) : Text(since, style: .timer)
        }
    }

    /// 停住的计时，h:mm:ss。
    private static func frozenText(_ interval: TimeInterval) -> Text {
        let seconds = max(0, Int(interval.rounded()))
        return Text(String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60))
    }
}

/// 顶部一行：牛头、可选的日期，右侧状态圆点 7 + 11/700。
struct WidgetHeader: View {
    let glyphSize: CGFloat
    var dateText: String?
    var dateSize: CGFloat = 10
    let statusLabel: String
    let tone: WidgetTone

    var body: some View {
        HStack(spacing: Spacing.s6) {
            WidgetCowGlyph(size: glyphSize)
            if let dateText {
                // 日期与状态都不省略 (fixedSize)，挤的时候只压中间的空白。
                Text(dateText).font(AppFont.ui(dateSize)).foregroundStyle(Palette.muted).fixedSize()
            }
            Spacer(minLength: Spacing.s2)
            HStack(spacing: 5) {
                Circle().fill(tone.color).frame(width: 7, height: 7)
                Text(statusLabel).font(AppFont.ui(11, .bold)).foregroundStyle(tone.color).fixedSize()
            }
        }
    }
}

/// 菜单栏同款牛头 (模板图，按 ink 着色)。
struct WidgetCowGlyph: View {
    let size: CGFloat

    var body: some View {
        Image(.cowGlyph).renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Palette.ink)
            .accessibilityHidden(true)
    }
}

/// 休息日的小牛。
struct WidgetMascot: View {
    let size: CGFloat

    var body: some View {
        Image(.cowMascot).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// 大数字：小标题、¥ + 数字，底边对齐 (同设计稿 Amount)。
struct WidgetAmountView: View {
    let label: String
    let amount: String
    var labelSize: CGFloat = 11
    var currencySize: CGFloat = 14
    var amountSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(label).font(AppFont.ui(labelSize)).foregroundStyle(Palette.muted).lineLimit(1)
            // ¥ 与数字按基线对齐，底边齐平 (按 .bottom 对齐时字框底下的留白不同，¥ 会偏低)。
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text("¥").font(AppFont.num(currencySize, .semibold))
                Text(amount)
                    .font(AppFont.num(amountSize, .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Palette.ink)
        }
    }
}

/// 一行「标题 …… 值」：小号底部、中号左栏没有进度条时用。值是计时时右对齐，计时文字会占满剩下的宽度。
struct WidgetFootRow: View {
    let stat: WidgetStat
    let clock: WidgetClock
    var valueColor: Color = Palette.ink

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            Text(stat.title)
                .font(AppFont.ui(10))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
            if let value = stat.value {
                clock.text(value)
                    .font(AppFont.num(12, .semibold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

/// 竖排的一项：标题 10 muted，下方数值 (等宽 `valueSize`/600)。中号右栏、大号统计行用。
struct WidgetStatView: View {
    let stat: WidgetStat
    let clock: WidgetClock
    var valueSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(stat.title).font(AppFont.ui(10)).foregroundStyle(Palette.muted).lineLimit(1)
            if let value = stat.value {
                clock.text(value)
                    .font(StatStyle.font(Self.text(value), numSize: valueSize))
                    .foregroundStyle(StatStyle.color(Self.text(value), isHighlighted: stat.isHighlighted))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 定字体与颜色用的文字；计时一律按数字处理。
    private static func text(_ value: WidgetValue) -> String {
        if case .text(let text) = value { return text }
        return "0"
    }
}

/// 单条进度条：line 底、`color` 填充，圆角为高度一半。
struct WidgetBar: View {
    let ratio: Double
    var height: CGFloat = 6
    var color: Color = Palette.money

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(Palette.line).overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: geometry.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// 大号的分段进度条 (设计稿 Timeline，高 8、圆角 4)：饭点与落在中间的请假是一小块 surface 色的间隔，同面板。
struct WidgetSegmentedBar: View {
    let segments: [ProgressSegment]

    private static let gap: CGFloat = 3
    private static let breakWidth: CGFloat = 16
    private static let height: CGFloat = 8
    private static let radius: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let breaks = CGFloat(max(segments.count - 1, 0))
            let usable = max(0, geometry.size.width - breaks * (Self.breakWidth + Self.gap * 2))
            HStack(spacing: Self.gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        RoundedRectangle(cornerRadius: Self.radius).fill(Palette.surface).frame(width: Self.breakWidth)
                    }
                    let width = usable * segment.share
                    RoundedRectangle(cornerRadius: Self.radius)
                        .fill(Palette.line)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: Self.radius).fill(Palette.money).frame(width: width * segment.filled)
                        }
                        .frame(width: width)
                }
            }
        }
        .frame(height: Self.height)
    }
}

/// 进度条下方一行：左计划上班、中间百分比 (money)、右计划下班，都是 10 号等宽。
struct WidgetTicks: View {
    let start: String
    let percent: String
    let end: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            Text(start).foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
            Text(percent).font(AppFont.num(10, .semibold)).foregroundStyle(Palette.money)
            Spacer(minLength: 0)
            Text(end).foregroundStyle(Palette.muted)
        }
        .font(AppFont.num(10))
        .lineLimit(1)
    }
}

/// 没有目标时的一行淡淡的提示：旗子 + 「给自己定个目标吧」。
struct WidgetEmptyGoal: View {
    let prompt: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            PhosphorIcon(.flagBanner, size: 11).iconOnTextBaseline(11).foregroundStyle(Palette.muted)
            Text(prompt).font(AppFont.ui(11)).foregroundStyle(Palette.muted).lineLimit(1)
        }
    }
}

/// 未完成引导：小牛 + 一句提示，居中。
struct WidgetSetupView: View {
    let setup: WidgetSetup
    let mascotSize: CGFloat

    var body: some View {
        VStack(spacing: Spacing.s6) {
            WidgetMascot(size: mascotSize)
            Text(setup.headline).font(AppFont.ui(15, .bold)).foregroundStyle(Palette.ink)
            Text(setup.message)
                .font(AppFont.ui(10))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
