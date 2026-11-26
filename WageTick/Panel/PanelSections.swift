import SwiftUI
import WageCore

/// 面板与表单共用的尺寸 (设计稿 P2、F5、F6 · 760)。
enum PanelMetrics {
    /// 面板、表单宽度。
    static let width: CGFloat = 360
    /// 面板圆角。
    static let cornerRadius = Radius.r14
    /// 底部操作按钮 (情绪按钮、表单的算了与保存) 高度。
    static let actionButtonHeight: CGFloat = 44
    /// 表单内容区各组之间的间距 (设计稿 F5、F6 Body)。
    static let formSectionGap: CGFloat = 26
    /// 进度区位置上的白干计时按钮 (我还没走、终于下班了) 高度。
    static let unpaidWorkButtonHeight: CGFloat = 48
}

/// 表单各段之间的 1pt 分隔线。
struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

/// 日期与状态行 (24 高)：左边日期与时间 (12/500，muted)，右边醒目的日状态 (圆点 8 + 17/700，按状态着色，无底色)。
/// 两段文字都上提 1：打包的 Noto Sans SC 行框上高下低，汉字墨迹中心比行框中心低约 0.05 em，上提后墨迹在 24 高里居中、与圆点中心齐。
struct PanelTopBar: View {
    let panel: TodayPanel

    private static let dotSize: CGFloat = 8
    private static let textLift: CGFloat = 1

    var body: some View {
        HStack {
            // 设计稿日期与时间之间空两格。
            Text("\(panel.dateText)  \(panel.timeText)")
                .font(AppFont.label)
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
                .offset(y: -Self.textLift)
            Spacer()
            HStack(spacing: Spacing.s6) {
                Circle().fill(tone).frame(width: Self.dotSize, height: Self.dotSize)
                Text(panel.statusLabel).font(AppFont.ui(17, .bold)).foregroundStyle(tone)
                    .offset(y: -Self.textLift)
            }
        }
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

/// 首页提示条 (节假日数据缺失、本月没有要上班的日子、扣款超过日薪)，在红绿灯那一行 (`HomeNoticeLayout`)，只占一行。
/// accentSoft 底、圆角 8、左右 8，warning 图标 13 + 12 号文字，都是 accent 色；文案原样取自快照。
/// 放得下就静止；放不下时跑马灯：停 1.5 秒，以每秒 30 pt 向左滚到结尾，停 1.5 秒回到开头，循环。
/// 有多条时一条播完 (放得下的停 4 秒) 换下一条。悬停时暂停，`.help` 给出这一条的全文。
/// 系统开了「减弱动态效果」时不滚动，放不下的截断。
struct PanelNoticeBanner: View {
    let texts: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var offset: CGFloat = 0
    @State private var phase = Phase.holdStart(elapsed: 0)
    @State private var isHovered = false
    @State private var textWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private enum Phase: Equatable {
        case holdStart(elapsed: Double)
        case scrolling
        case holdEnd(elapsed: Double)
    }

    /// 开头、结尾各停多久 (秒)。
    private static let hold = 1.5
    /// 放得下的那条在多条之间停多久 (秒)。
    private static let holdFitting = 4.0
    /// 滚动速度 (pt/秒)。
    private static let speed: CGFloat = 30
    /// 每一步的间隔 (秒)。
    private static let tick = 1.0 / 30

    private var text: String { texts[min(index, texts.count - 1)] }
    private var overflow: CGFloat { max(0, textWidth - viewportWidth) }

    var body: some View {
        HStack(spacing: Spacing.s6) {
            PhosphorIcon(.warning, size: 13)
            GeometryReader { geometry in
                Group {
                    if reduceMotion {
                        Text(text).lineLimit(1).truncationMode(.tail)
                            .frame(width: geometry.size.width, alignment: .leading)
                    } else {
                        Text(text).lineLimit(1).fixedSize()
                            .background(GeometryReader { Color.clear.preference(key: TextWidthKey.self, value: $0.size.width) })
                            .offset(x: -offset)
                    }
                }
                .frame(height: geometry.size.height)
                .onAppear { viewportWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { _, width in viewportWidth = width }
            }
            .clipped()
            .onPreferenceChange(TextWidthKey.self) { textWidth = $0 }
        }
        .font(AppFont.caption)
        .foregroundStyle(Palette.accent)
        .padding(.horizontal, Spacing.s8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control))
        .onHover { isHovered = $0 }
        .help(text)
        .task(id: texts) {
            index = 0
            restart()
            while !Task.isCancelled {
                // 只有一条且不用滚时没什么可推进的，放慢检查 (文字宽度量出来之前也先按这个等)。
                let idle = texts.count < 2 && (reduceMotion || overflow <= 0)
                try? await Task.sleep(for: .seconds(idle ? 0.5 : Self.tick))
                if !isHovered && !idle { step() }
            }
        }
    }

    private func restart() {
        offset = 0
        phase = .holdStart(elapsed: 0)
    }

    /// 往前走一步。放得下 (或减弱动态效果) 时只计时，到点换下一条；放不下时按停、滚、停推进。
    private func step() {
        let scrolls = !reduceMotion && overflow > 0
        switch phase {
        case .holdStart(let elapsed):
            let next = elapsed + Self.tick
            if scrolls {
                phase = next >= Self.hold ? .scrolling : .holdStart(elapsed: next)
            } else if next >= Self.holdFitting {
                advance()
            } else {
                phase = .holdStart(elapsed: next)
            }
        case .scrolling:
            offset = min(overflow, offset + Self.speed * Self.tick)
            if offset >= overflow { phase = .holdEnd(elapsed: 0) }
        case .holdEnd(let elapsed):
            let next = elapsed + Self.tick
            if next >= Self.hold { advance() } else { phase = .holdEnd(elapsed: next) }
        }
    }

    /// 回到开头；有多条时换下一条。
    private func advance() {
        if texts.count > 1 { index = (index + 1) % texts.count }
        restart()
    }
}

/// 提示条文字的自然宽度，判断要不要滚动。
private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 主数字区 (108 高)：小标题 13 muted (行高 18)，空 6，¥ (等宽 26/600) + 数字 (等宽 54/700，字距 −1.5) 基线对齐 (高 60)，
/// 空 8，说明行 12 muted (行高 16，单行)。左对齐。主数字与说明行原样取自快照；¥ 拆出来单独排版，与数字同色。
struct PanelHero: View {
    /// 主数字上方的小标题，如「今日已赚」。
    let label: String
    let headline: String
    let caption: String
    /// 主数字的颜色：平时 ink，白干中 loss。
    var tone: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(AppFont.body).foregroundStyle(Palette.muted)
                .frame(height: 18)
            amount
                .frame(height: 60)
                .padding(.top, Spacing.s6)
            Text(caption)
                .font(AppFont.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 16)
                .padding(.top, Spacing.s8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .foregroundStyle(tone)
    }

    /// 把快照里的「¥571.4286」拆成货币符号与数字，只为分开排版；没有 ¥ 时原样显示。
    private static func split(_ headline: String) -> (String?, String) {
        guard headline.hasPrefix("¥") else { return (nil, headline) }
        return ("¥", String(headline.dropFirst()))
    }
}

/// 休息日 (不在白干计时) 主数字区与进度区合成的一整块：横排、垂直居中、在整宽里水平居中。
/// 左边小牛 128，空 20，右边一列左对齐：「今天休息」30/700 ink，下面公文包 12 + 下一个上班日 (12 muted)，没有下一个上班日时不显示这一行。
/// 右边一列按墨迹居中：打包的 Noto Sans SC 行框上高下低，30 号字的墨迹比行框中心低约 1.5，加上第二行再低 2，
/// 所以整列上提 (两行 3.5、一行 1.5)，文字墨迹的中心与小牛的中心 (整块中线) 齐。
struct PanelRestHero: View {
    let rest: RestPanel

    private static let mascotSize: CGFloat = 128
    private var textLift: CGFloat { rest.nextAttendanceDate == nil ? 1.5 : 3.5 }

    var body: some View {
        HStack(spacing: Spacing.s20) {
            Image(.cowMascot)
                .resizable()
                .scaledToFit()
                .frame(width: Self.mascotSize, height: Self.mascotSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s6) {
                Text(rest.headline).font(AppFont.ui(30, .bold)).foregroundStyle(Palette.ink)
                if let date = rest.nextAttendanceDate {
                    HStack(spacing: Spacing.s4) {
                        PhosphorIcon(.briefcase, size: 12)
                        Text(date).font(AppFont.caption)
                    }
                    .foregroundStyle(Palette.muted)
                }
            }
            .offset(y: -textLift)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 工作进度区 (56 高)：0–18 是「已工作 4 / 7 小时」(13/500 ink) 与百分比 (等宽 13/600 money)，
/// 26–36 是分段进度条，42–56 是计划上班与下班时刻 (等宽 11 muted)。
/// 第一行上提 1：打包的 Noto Sans SC 13 号的行高 19 比这一行的 18 高，墨迹又偏行框下方，不提的话字底贴着 18 的下沿。
struct PanelProgress: View {
    let progress: WorkProgress

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .lastTextBaseline) {
                Text(progress.label).font(AppFont.bodyMedium).foregroundStyle(Palette.ink)
                Spacer()
                Text(progress.percent).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.money)
            }
            .frame(height: 18)
            .offset(y: -1)
            SegmentedProgressBar(segments: progress.segments)
                .padding(.top, Spacing.s8)
            HStack {
                Text(progress.startClock)
                Spacer()
                Text(progress.endClock)
            }
            .font(AppFont.numSmall)
            .foregroundStyle(Palette.muted)
            .frame(height: 14)
            .padding(.top, Spacing.s6)
        }
        .frame(maxHeight: .infinity, alignment: .top)
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

/// 统计卡 (320×64)：surface 底、圆角 12、左右内边距 16，内容垂直居中。
/// 三格等宽、左对齐，格与格之间没有竖线；只有两格时也按三等分的格宽排，第三格空着。
/// 每格标题 11 muted，空 4，值 15 (数字等宽 15/600，文字值与颜色见 `StatStyle`)。
struct PanelStatsCard: View {
    let stats: [StatItem]

    private static let columns = 3
    private static let valueSize: CGFloat = 15

    var body: some View {
        // 顶对齐：文字值 (如「正在休息」) 比数字矮，三格的标题仍在同一条线上。
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stats.prefix(Self.columns).enumerated()), id: \.offset) { _, item in
                cell(item)
            }
            ForEach(0..<max(0, Self.columns - stats.count), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Spacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private func cell(_ item: StatItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(item.title).font(AppFont.small).foregroundStyle(Palette.muted)
            Text(item.value)
                .font(StatStyle.font(item.value, numSize: Self.valueSize))
                .foregroundStyle(StatStyle.color(item.value, isHighlighted: item.isHighlighted))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
