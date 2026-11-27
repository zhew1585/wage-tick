import SwiftUI
import WageCore

/// 首页攒钱队列 (PRD F9，首页改版定稿)：320×104 的一块，没有标题行；文字和进度原样取自快照的 `GoalCard`、`GoalQueueSection`。
/// 按目标个数排法不同，卡片间距 8、圆角 12，点任何一张目标卡都进入目标页：
/// - 没有目标：整块一张空状态卡，旗子、「给自己定个目标吧」和长得像按钮的「新目标」(整张卡是一个按钮)。
/// - 1 个：整块一张累计中卡片。
/// - 2 个：左边累计中大卡 208×104，右边排队中第一个的整高卡 104×104。
/// - 3 个及以上：左边大卡，右边上下两张排队中小卡 104×48；更多的不显示，也不加标记。
struct GoalCardView: View {
    let card: GoalCard
    /// 排队部分；没有排队中目标时为 nil。只用 `upcoming` (按队列顺序，最多 2 个)。
    let queue: GoalQueueSection?
    let openGoals: () -> Void

    /// 累计中大卡的宽度 (2 个及以上目标时)，右边一列 104 宽。
    private static let sideWidth: CGFloat = 104

    var body: some View {
        switch card {
        case .empty(let prompt):
            EmptyGoalCard(prompt: prompt, openGoals: openGoals)
        case .active(let goal):
            let upcoming = Array((queue?.upcoming ?? []).prefix(2))
            HStack(spacing: Spacing.s8) {
                tappable { ActiveGoalCardView(goal: goal, isWide: upcoming.isEmpty) }
                switch upcoming.count {
                case 0:
                    EmptyView()
                case 1:
                    tappable { QueuedGoalTile(goal: upcoming[0], showsFinish: true) }
                        .frame(width: Self.sideWidth)
                default:
                    VStack(spacing: Spacing.s8) {
                        ForEach(upcoming) { goal in
                            tappable { QueuedGoalTile(goal: goal, showsFinish: false) }
                        }
                    }
                    .frame(width: Self.sideWidth)
                }
            }
        }
    }

    /// 点一下进入目标页；悬停、按下时叠一层底。
    private func tappable(_ label: () -> some View) -> some View {
        Button(action: openGoals) { label().contentShape(Rectangle()) }
            .buttonStyle(.highlight(radius: Radius.card))
    }
}

/// 累计中目标的卡片：accentSoft 底、圆角 12，三行上下撑开。
/// 名称行 (高 20)：旗子 14、名称 14/600 (放不下截断)，右边百分比等宽 13/600 accent。
/// 金额行 (高 27，底对齐)：累计额等宽 20/600 + 「/ 目标额」等宽 12 muted，完整显示，实在放不下才缩小。
/// 进度行 (高 16)：大卡里是进度条 (最宽 120) 与预计完成日 11 muted 靠右，字底与进度条下沿对齐。
/// 整宽卡里预计完成日在金额行右侧，进度条整宽、紧跟金额行下面，进度行留空。
/// 大卡里预计完成日较长 (带年份，如「2027年7月」) 时进度条让出宽度，卡片本身不能被撑宽，否则整个首页会被撑出 320。
private struct ActiveGoalCardView: View {
    let goal: ActiveGoalCard
    /// 只有这一个目标、占满整块 320 宽。
    let isWide: Bool

    private static let barWidth: CGFloat = 120
    /// 预计完成日较长时进度条最窄缩到多少。
    private static let minBarWidth: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                PhosphorIcon(.flagBanner, size: 14).iconOnTextBaseline().foregroundStyle(Palette.accent)
                Text(goal.name).font(AppFont.section).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: Spacing.s6)
                Text(goal.percentText).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.accent)
            }
            .frame(height: 20)
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
                Text(goal.accumulatedText).font(AppFont.num(20, .semibold)).foregroundStyle(Palette.ink)
                    .layoutPriority(1)
                Text("/ \(goal.targetText)").font(AppFont.numCaption).foregroundStyle(Palette.muted)
                    .layoutPriority(1)
                if isWide {
                    Spacer(minLength: Spacing.s8)
                    // 按文字基线对齐时汉字的字底比数字低约 1，日期上提 1，字底才和左边累计额的字底在一条线上。
                    finish.alignmentGuide(.lastTextBaseline) { $0[.lastTextBaseline] + 1 }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: 27, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if isWide { wideBar }
            }
            Spacer(minLength: 0)
            if isWide {
                // 第三行只占位，三行的高度与多个目标时的大卡一样，名称行、金额行才和大卡同高。
                Color.clear.frame(height: 16)
            } else {
                // 预计完成日的字底落在进度条下沿：按文字基线对齐，汉字的字底比基线低约 1，进度条的下沿再往下 1。
                HStack(alignment: .lastTextBaseline, spacing: Spacing.s8) {
                    GoalProgressBar(progress: goal.progress)
                        .frame(minWidth: Self.minBarWidth, maxWidth: Self.barWidth)
                        .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 1 }
                    Spacer(minLength: 0)
                    finish
                }
                .frame(height: 16, alignment: .bottom)
            }
        }
        .padding(.vertical, isWide ? Spacing.s16 : Spacing.s14)
        .padding(.horizontal, isWide ? Spacing.s14 : Spacing.s12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    /// 整宽卡的进度条：整宽，上沿在金额行下沿往下 8 (卡内 75.5–81.5)。
    /// 挂在金额行底边一条零高的线上往下长，不放进三行里，金额行的位置不受它影响；第三行留空，卡底空出 22.5。
    private var wideBar: some View {
        Color.clear.frame(height: 0).overlay(alignment: .top) {
            GoalProgressBar(progress: goal.progress).padding(.top, Spacing.s8)
        }
    }

    @ViewBuilder
    private var finish: some View {
        if let finishText = goal.finishText {
            Text(finishText).font(AppFont.small).foregroundStyle(Palette.muted).lineLimit(1).fixedSize()
        }
    }
}

/// 排队中目标的卡片：纸底、1 pt line 描边、圆角 12，名称 12/600 ink、目标额等宽 13/600 ink，都单行。
/// 小卡 104×48 (内边距上下 7、左右 10) 只有这两行；整高卡 104×104 (内边距上下 14) 三行上下撑开，第三行是预计完成日 11 muted，
/// 三行分别和旁边大卡的三行对齐。
private struct QueuedGoalTile: View {
    let goal: QueuedGoalCard
    /// 整高卡：三行撑开并带预计完成日。
    let showsFinish: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(goal.name).font(AppFont.captionSemibold).foregroundStyle(Palette.ink)
                .frame(height: showsFinish ? 20 : nil)
            if showsFinish { Spacer(minLength: 0) }
            Text(goal.amountText).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.ink)
                .frame(height: showsFinish ? 27 : nil, alignment: .bottom)
            if showsFinish {
                Spacer(minLength: 0)
                Text(goal.finishText ?? "").font(AppFont.small).foregroundStyle(Palette.muted)
                    .frame(height: 16, alignment: .bottom)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.vertical, showsFinish ? Spacing.s14 : 7)
        .padding(.horizontal, Spacing.s10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.line))
        .help(goal.estimate)
    }
}

/// 队列为空：纸底、1 pt line 描边的整块卡，横排、垂直居中，左右 16、间距 12：
/// accentSoft 圆 36 里放旗子 16 (accent)、提示 14/600、最右边「新目标」(长得像次要按钮，高 32，加号 12 + 13/500)。
/// 整张卡是一个按钮，点击、键盘聚焦、悬停高亮都只在卡片这一层；「新目标」只是画出来的样子，不另外接点击。
private struct EmptyGoalCard: View {
    let prompt: String
    let openGoals: () -> Void

    var body: some View {
        Button(action: openGoals) {
            HStack(spacing: Spacing.s12) {
                PhosphorIcon(.flagBanner, size: 16)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .background(Palette.accentSoft, in: Circle())
                Text(prompt).font(AppFont.section).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: 0)
                NewGoalBadge()
            }
            .padding(.horizontal, Spacing.s16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bg, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: Radius.card))
    }
}

/// 空状态卡里的「新目标」：与 `.secondary(fullWidth: false, height: 32)` 的次要按钮静止时逐像素相同 (surface 底、圆角 8、左右 14、
/// 加号 14 宽框里 12 + 间距 6 + 13/500 ink)，但不是按钮，不接点击、不进焦点，悬停时只有外面整张卡的那层高亮。
private struct NewGoalBadge: View {
    var body: some View {
        HStack(spacing: Spacing.s6) {
            PhosphorIcon(.plus, size: 12)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 14, height: 14)
            Text("新目标")
        }
        .font(AppFont.bodyMedium)
        .foregroundStyle(Palette.ink)
        .lineLimit(1)
        .padding(.horizontal, Spacing.s14)
        .frame(minHeight: 32)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.control))
    }
}

/// 目标进度条：高 6、圆角 3，line 底、accent 填充。
private struct GoalProgressBar: View {
    /// 进度条比例，0 至 1。
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Palette.line)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: 6)
    }
}
