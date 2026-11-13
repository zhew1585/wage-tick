import SwiftUI
import WageCore

/// 面板与表单共用的尺寸 (设计稿 P2、F5、F6 · 760)。
enum PanelMetrics {
    /// 面板、表单宽度。
    static let width: CGFloat = 360
    /// 表单头图标题栏右侧小字离右边的距离，让开右上角的钉住按钮 (12 + 20 + 16)。
    static let pinInset: CGFloat = 48
    /// 面板圆角。
    static let cornerRadius = Radius.r14
    /// 进度区位置上的白干计时按钮 (我还没走、终于下班了) 高度。
    static let unpaidWorkButtonHeight: CGFloat = 48
}

/// 面板各段之间的 1pt 分隔线。
struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// 面板顶部一行：左边日期与时间 (12/500，muted)，右边醒目的日状态 (圆点 + 17/700，按状态着色，无底色)。
struct PanelTopBar: View {
    let panel: TodayPanel

    private static let dotSize: CGFloat = 8

    var body: some View {
        HStack {
            // 设计稿日期与时间之间空两格。
            Text("\(panel.dateText)  \(panel.timeText)")
                .font(AppFont.label)
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
            Spacer()
            HStack(spacing: Spacing.s6) {
                Circle().fill(tone).frame(width: Self.dotSize, height: Self.dotSize)
                Text(panel.statusLabel).font(AppFont.ui(17, .bold)).foregroundStyle(tone)
            }
        }
        .padding(EdgeInsets(top: Spacing.s16, leading: Spacing.screen, bottom: 0, trailing: Spacing.screen))
    }

    /// 日状态的颜色：应出勤日 money，休息日 accent，白干计时中 loss。
    private var tone: Color {
        switch panel.body {
        case .attendance: Palette.money
        case .rest: Palette.accent
        case .unpaidWork: Palette.loss
        }
    }
}

/// 面板顶部提示条，如节假日数据缺失 (AC-HOME-08)。文案原样取自快照。
struct PanelNoticeBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            PhosphorIcon(.warning, size: 13).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            Text(text).font(AppFont.caption).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Palette.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s8)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control))
    }
}

/// 主数字区 (设计稿 Hero)：小标题 13、¥ (JetBrains Mono 26/600) + 大号数字 (54/700)、下方一行小字 12，间距 6。
/// 主数字与小字原样取自快照；¥ 拆出来单独排版，与数字同色，底边对齐。
struct PanelHero: View {
    /// 主数字上方的小标题，如「今日已赚」。
    let label: String
    let headline: String
    let caption: String
    /// 快照里的额外提示，如扣款超过日薪 (PRD 4.3.5 #6)。
    var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(label).font(AppFont.body).foregroundStyle(Palette.muted)
            amount
            Text(caption)
                .font(AppFont.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let notice {
                Text(notice).font(AppFont.caption).foregroundStyle(Palette.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 30, leading: Spacing.screen, bottom: 28, trailing: Spacing.screen))
    }

    private var amount: some View {
        let (currency, number) = Self.split(headline)
        // ¥ 与数字按基线对齐，底边齐平 (按 .bottom 对齐时字框底下的留白不同，¥ 会偏低)。
        return HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
            if let currency {
                Text(currency).font(AppFont.num(26, .semibold))
            }
            Text(number)
                .font(AppFont.num(54, .bold))
                .tracking(-1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(Palette.ink)
    }

    /// 把快照里的「¥571.4286」拆成货币符号与数字，只为分开排版；没有 ¥ 时原样显示。
    private static func split(_ headline: String) -> (String?, String) {
        guard headline.hasPrefix("¥") else { return (nil, headline) }
        return ("¥", String(headline.dropFirst()))
    }
}

/// 工作进度区：「已工作 4 / 7 小时」与百分比，下方分段进度条，再下方计划上班与下班时刻，间距 10。
struct PanelProgress: View {
    let progress: WorkProgress

    var body: some View {
        VStack(spacing: Spacing.s10) {
            HStack(alignment: .lastTextBaseline) {
                Text(progress.label).font(AppFont.bodyMedium).foregroundStyle(Palette.ink)
                Spacer()
                Text(progress.percent).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.money)
            }
            SegmentedProgressBar(segments: progress.segments)
            HStack {
                Text(progress.startText)
                Spacer()
                Text(progress.endText)
            }
            .font(AppFont.numSmall)
            .foregroundStyle(Palette.muted)
        }
    }
}

/// 分段进度条 (高 10、圆角 3)：每段宽度按 `share` 分配，段与段之间是一小块 surface 色的饭点。
private struct SegmentedProgressBar: View {
    let segments: [ProgressSegment]

    private static let gap: CGFloat = 3
    private static let lunchWidth: CGFloat = 16
    private static let height: CGFloat = 10
    private static let radius: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let breaks = CGFloat(max(segments.count - 1, 0))
            let usable = max(0, geometry.size.width - breaks * (Self.lunchWidth + Self.gap * 2))
            HStack(spacing: Self.gap) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        RoundedRectangle(cornerRadius: Self.radius).fill(Palette.surface).frame(width: Self.lunchWidth)
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

/// 统计行 (设计稿 Stats)：上下各一条分隔线，内边距 16 / 20；各项平分宽度，项与项之间一条 1×34 的竖线，竖线后的项左边空 14。
/// 标题 11 muted，数值 JetBrains Mono 17/600；三项时最后一项 (本月累计，位数最多) 用 15。扣款 (以「−」开头的金额) 用 loss 色。
struct PanelStatsRow: View {
    let stats: [StatItem]

    private static let dividerHeight: CGFloat = 34
    private static let cellLeading: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            PanelDivider()
            HStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Rectangle().fill(Palette.line).frame(width: 1, height: Self.dividerHeight)
                    }
                    cell(item, valueSize: stats.count == 3 && index == 2 ? 15 : 17)
                        .padding(.leading, index > 0 ? Self.cellLeading : 0)
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, Spacing.s16)
            PanelDivider()
        }
    }

    private func cell(_ item: StatItem, valueSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(item.title).font(AppFont.small).foregroundStyle(Palette.muted)
            Text(item.value)
                .font(StatStyle.font(item.value, numSize: valueSize))
                .foregroundStyle(StatStyle.color(item.value, isHighlighted: item.isHighlighted))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 大胆版进度格 (设计稿「大胆风格」)：左上说明 13/700，右上大字 (Archivo Black 22，白干用红色、平时橙色)；
/// 下面一排圆角小格，每格 1 小时，已过的墨色 (白干填红)，当前这一小时填一部分；下班后白干在末尾多一格红色超时。
/// 文字与格数原样取自快照的 `HourBlocks`。
struct HourBlocksView: View {
    let blocks: HourBlocks

    private static let height: CGFloat = 18

    var body: some View {
        VStack(spacing: Spacing.s8) {
            HStack(alignment: .lastTextBaseline) {
                Text(blocks.label).font(AppFont.ui(13, .bold)).foregroundStyle(Palette.ink)
                Spacer()
                Text(blocks.value).font(AppFont.heavy(22)).foregroundStyle(blocks.isUnpaid ? Palette.hot : Palette.accent)
            }
            HStack(spacing: Spacing.s4) {
                ForEach(0..<blocks.count, id: \.self) { index in
                    cell(fill: min(max(blocks.filled - Double(index), 0), 1))
                }
                if blocks.overtime {
                    RoundedRectangle(cornerRadius: Radius.r5).fill(Palette.hot)
                }
            }
            .frame(height: Self.height)
        }
    }

    /// 一格：`fill` 为这格填了多少 (0 至 1)。
    private func cell(fill: Double) -> some View {
        // 休息日被迫营业的格子填白干的红；下班后白干的工时格仍是墨色，超时那格才是红的。
        let color = blocks.isUnpaid && !blocks.overtime ? Palette.hot : Palette.ink
        return RoundedRectangle(cornerRadius: Radius.r5)
            .fill(Palette.surface)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Rectangle().fill(color).frame(width: geometry.size.width * fill)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.r5))
    }
}

/// 大胆版统计行：各项平分宽度、居中，数值 Archivo Black 20，标题 11 muted，项与项之间一条细竖线，没有上下分隔线。
/// 扣款 (以「−」开头) 用 loss 色，本月累计用 money 色，高亮项 (距离周末) 用 accent。
struct BoldStatsRow: View {
    let stats: [StatItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle().fill(Palette.line).frame(width: 1, height: 34)
                }
                VStack(spacing: Spacing.s3) {
                    Text(item.value)
                        .font(AppFont.heavy(20))
                        .foregroundStyle(color(item))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(item.title).font(AppFont.small).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(_ item: StatItem) -> Color {
        if item.value.hasPrefix("−") { return Palette.loss }
        if item.isHighlighted { return Palette.accent }
        if item.title == "本月累计" { return Palette.money }
        return Palette.ink
    }
}
