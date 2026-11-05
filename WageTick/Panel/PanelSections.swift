import SwiftUI
import WageCore

/// 面板与表单共用的尺寸 (设计稿 P2、F5、F6)。
enum PanelMetrics {
    /// 面板、表单宽度。
    static let width: CGFloat = 360
    /// 面板圆角。
    static let cornerRadius = Radius.r14
    /// 进度区 / 白干按钮区高度 (含下边距 18)：两者一样高，上班中与白干中的面板总高度一致 (AC-HOME-11)。
    static let progressZoneHeight: CGFloat = 55
    /// 统计行高度。
    static let statsHeight: CGFloat = 68
}

/// 面板各段之间的 1pt 分隔线。
struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// 面板顶部：日期与时间 (12/500，muted)，右侧状态 Chip。
struct PanelTopBar: View {
    let panel: TodayPanel

    var body: some View {
        HStack {
            // 设计稿日期与时间之间空两格。
            Text("\(panel.dateText)  \(panel.timeText)")
                .font(AppFont.label)
                .foregroundStyle(Palette.muted)
            Spacer()
            Chip(panel.statusLabel, tone: tone)
        }
        .padding(EdgeInsets(top: Spacing.s16, leading: Spacing.screen, bottom: 0, trailing: Spacing.screen))
    }

    /// 状态 Chip 的色调：应出勤日 money，休息日 accent，白干计时中 loss。
    private var tone: Chip.Tone {
        switch panel.body {
        case .attendance: .money
        case .rest: .accent
        case .unpaidWork: .loss
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

/// 主数字区：小标题、¥ + 大号数字 (JetBrains Mono 40/700)、下方一行小字。
/// 主数字与小字原样取自快照；¥ 拆出来单独上色 (赚钱 money，倒贴 loss)。
struct PanelHero: View {
    /// 主数字上方的小标题，如「今日已赚」。
    let label: String
    let headline: String
    let caption: String
    /// 快照里的额外提示，如扣款超过日薪 (PRD 4.3.5 #6)。
    var notice: String?
    let currencyColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(label).font(AppFont.caption).foregroundStyle(Palette.muted)
            amount
            Text(caption)
                .font(AppFont.caption)
                .foregroundStyle(Palette.muted)
                // 固定单行，上班中与白干中的面板总高度一致 (AC-HOME-11)。
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let notice {
                Text(notice).font(AppFont.caption).foregroundStyle(Palette.accent).padding(.top, Spacing.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: Spacing.s14, leading: Spacing.screen, bottom: 18, trailing: Spacing.screen))
    }

    private var amount: some View {
        let (currency, number) = Self.split(headline)
        return HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
            if let currency {
                Text(currency).font(AppFont.num(22, .semibold)).foregroundStyle(currencyColor)
            }
            Text(number)
                .font(AppFont.num(40, .bold))
                .tracking(-1)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// 把快照里的「¥571.4286」拆成货币符号与数字，只为分开排版；没有 ¥ 时原样显示。
    private static func split(_ headline: String) -> (String?, String) {
        guard headline.hasPrefix("¥") else { return (nil, headline) }
        return ("¥", String(headline.dropFirst()))
    }
}

/// 工作进度区：「已工作 4 / 7 小时」与百分比，下方分段进度条。
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
        }
    }
}

/// 分段进度条 (高 8、圆角 3)：每段宽度按 `share` 分配，段与段之间是一小块 surface 色的午休。
private struct SegmentedProgressBar: View {
    let segments: [ProgressSegment]

    private static let gap: CGFloat = 3
    private static let lunchWidth: CGFloat = 16
    private static let height: CGFloat = 8
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

/// 统计行 (高 68)：两项时中间一条竖线 (上班中、休息日)，三项时平分 (已下班、白干中)。
/// 标题 11 muted，数值 JetBrains Mono 17/600；扣款 (以「−」开头的金额) 用 loss 色。
struct PanelStatsRow: View {
    let stats: [StatItem]

    var body: some View {
        HStack(spacing: stats.count == 2 ? 0 : Spacing.s8) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, item in
                if stats.count == 2 && index == 1 {
                    Rectangle().fill(Palette.line).frame(width: 1, height: 34)
                }
                cell(item).padding(.leading, stats.count == 2 && index == 1 ? Spacing.s16 : 0)
            }
        }
        .padding(.horizontal, Spacing.screen)
        .frame(height: PanelMetrics.statsHeight)
    }

    private func cell(_ item: StatItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(AppFont.small).foregroundStyle(Palette.muted)
            Text(item.value)
                .font(AppFont.numStat)
                .foregroundStyle(item.value.hasPrefix("−") ? Palette.loss : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 今天的扣钱明细，每笔可编辑、删除 (AC-FINE-04、PRD 4.4.1 #1)。设计稿没有这一段，按统计行的字号排。
struct PanelDeductionList: View {
    let items: [DeductionItem]
    let edit: (DeductionItem) -> Void
    let delete: (DeductionItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            ForEach(items) { item in
                HStack(spacing: Spacing.s8) {
                    PhosphorIcon(.trendDown, size: 13).foregroundStyle(Palette.loss)
                    Text(item.title).font(AppFont.captionSemibold).foregroundStyle(Palette.ink)
                    if let detail = item.detail {
                        Text(detail).font(AppFont.small).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                    Spacer(minLength: Spacing.s4)
                    Text(item.amount).font(AppFont.numBody).foregroundStyle(Palette.loss)
                    iconButton(.pencilSimple, help: "编辑") { edit(item) }
                    iconButton(.trash, help: "删除") { delete(item) }
                }
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s12)
    }

    private func iconButton(_ icon: Phosphor, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PhosphorIcon(icon, size: 13)
                .foregroundStyle(Palette.muted)
                .padding(Spacing.s2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
