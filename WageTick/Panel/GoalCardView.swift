import SwiftUI
import WageCore

/// 面板目标区「攒钱队列」(PRD F9，版面同大胆版设计稿「首页」，经典视觉)：文字和进度原样取自快照的 `GoalCard`、`GoalQueueSection`。
/// 累计中目标是一张白底描边卡 (`BoldGoalCard`)，下面排队中的目标缩成并排的小卡 (与累计中合计最多 3 个)。
/// 队列为空时换成描边的空状态卡：旗子、「给自己定个目标吧」、一行小字和「新目标」按钮，按钮进入目标管理。
/// 面板放不下时按 `density` 收紧：先少列排队中目标，空状态换成一行可点的提示。
struct GoalCardView: View {
    let card: GoalCard
    /// 排队部分；没有排队中目标时为 nil。只用 `upcoming`，旧的展开收起 (`queued`、`toggleTitle`) 不再用。
    let queue: GoalQueueSection?
    /// 标题右侧的目标总数，如「3 个目标」；没有未完成目标时为 nil。
    let countText: String?
    let density: GoalDensity
    let openGoals: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s8) {
            switch card {
            case .empty(let prompt):
                switch density {
                case .full: EmptyGoalCard(prompt: prompt, showsButton: true, openGoals: openGoals)
                case .oneQueued: EmptyGoalCard(prompt: prompt, showsButton: false, openGoals: openGoals)
                case .minimal: EmptyGoalRow(prompt: prompt, openGoals: openGoals)
                }
            case .active(let goal):
                Button(action: openGoals) {
                    BoldGoalCard(goal: goal, trailing: countText).contentShape(Rectangle())
                }
                .buttonStyle(.highlight(radius: Radius.r10))
                let upcoming = (queue?.upcoming ?? []).prefix(density.queuedLimit)
                if !upcoming.isEmpty {
                    QueuedGoalChips(goals: Array(upcoming))
                }
            }
        }
    }
}

/// 攒钱队列的松紧：面板从 `full` 起依次试，用第一个放得下的。
enum GoalDensity {
    /// 排队中最多列 2 个 (与累计中合计 3 个)，空状态用整张卡。
    case full
    /// 排队中只列 1 个，空状态卡不带按钮、整张可点。
    case oneQueued
    /// 只留累计中卡片，空状态用一行提示。
    case minimal

    /// 最多列几个排队中目标。
    var queuedLimit: Int {
        switch self {
        case .full: 2
        case .oneQueued: 1
        case .minimal: 0
        }
    }
}

/// 累计中目标卡 (经典视觉)：白底、line 描边、圆角 10。左上 accent-soft 底的「正在攒」标签与名称 14/600，右上目标总数 (或队列位置) 11 muted；
/// 中间累计额 (JetBrains Mono 20/600) + 「/ 目标金额」，右侧 accent 百分比 (17/600)；下面 line 底、accent 填充的进度条，最下一行预计 11 muted。
/// 目标页 (`GoalsView`) 也用这张卡。
struct BoldGoalCard: View {
    let goal: ActiveGoalCard
    /// 右上角的小字，如「3 个目标」「队列 1/4」。
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            HStack(spacing: Spacing.s6) {
                GoalTag(text: "正在攒")
                Text(goal.name).font(AppFont.section).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: Spacing.s8)
                if let trailing {
                    Text(trailing).font(AppFont.numSmall).foregroundStyle(Palette.muted)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
                Text(BoldNumber.grouped(goal.accumulatedText)).font(AppFont.num(20, .semibold)).foregroundStyle(Palette.ink)
                Text("/ \(BoldNumber.grouped(goal.targetText).replacingOccurrences(of: "¥", with: ""))")
                    .font(AppFont.numCaption).foregroundStyle(Palette.muted)
                Spacer(minLength: Spacing.s8)
                Text("\(Int((goal.progress * 100).rounded(.down)))%").font(AppFont.numStat).foregroundStyle(Palette.accent)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            GoalProgressBar(progress: goal.progress)
            Text(goal.estimate).font(AppFont.small).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .padding(.vertical, Spacing.s14)
        .padding(.horizontal, Spacing.s16)
        .goalCardBackground()
    }
}

/// 目标卡左上的小标签 (「正在攒」「还没目标」)：accent-soft 底、accent 字 10/700、圆角 4。
private struct GoalTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFont.ui(10, .bold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, Spacing.s2)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.r4))
    }
}

extension View {
    /// 经典卡片底：白底 (card)、1pt line 描边、圆角 10。
    func goalCardBackground(radius: CGFloat = Radius.r10) -> some View {
        background(Palette.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.line))
    }
}

/// 排队中目标缩成并排的小卡：白底 line 描边、圆角 8，名称 12/600 墨色，右侧预计到手的日期 10 muted。悬停显示完整预计。
private struct QueuedGoalChips: View {
    let goals: [QueuedGoalCard]

    var body: some View {
        HStack(spacing: Spacing.s8) {
            ForEach(goals) { goal in
                HStack(spacing: Spacing.s6) {
                    Text(goal.name).font(AppFont.captionSemibold).foregroundStyle(Palette.ink)
                    Spacer(minLength: Spacing.s4)
                    // 设计稿只写日期 (「11月26日」)，小卡窄，去掉快照短版预计前面的「预计」。
                    Text(goal.shortEstimate.replacingOccurrences(of: "预计 ", with: ""))
                        .font(AppFont.num(10)).foregroundStyle(Palette.muted)
                }
                .lineLimit(1)
                .padding(.horizontal, Spacing.s12)
                .padding(.vertical, Spacing.s8)
                .frame(maxWidth: .infinity)
                .goalCardBackground(radius: Radius.r8)
                .help(goal.estimate)
            }
        }
    }
}

/// 队列为空：和累计中目标卡 (`BoldGoalCard`) 同一结构、同一高度，当成一张「什么都还没攒」的卡：
/// 第一行「还没目标」标签与「写下想要的东西」、右上「队列 0」；第二行「¥0 / ?」与 accent「0%」；空进度条；
/// 最下面一行小字，右侧 accent「定个目标 ›」。整张卡可点，进入目标管理 (同有目标时)。
private struct EmptyGoalCard: View {
    let prompt: String
    let showsButton: Bool
    let openGoals: () -> Void

    var body: some View {
        Button(action: openGoals) { card.contentShape(Rectangle()) }
            .buttonStyle(.highlight(radius: Radius.r10))
            .accessibilityLabel(prompt)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            HStack(spacing: Spacing.s6) {
                GoalTag(text: "还没目标")
                Text("写下想要的东西").font(AppFont.section).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: Spacing.s8)
                Text("队列 0").font(AppFont.numSmall).foregroundStyle(Palette.muted)
            }
            HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
                Text("¥0").font(AppFont.num(20, .semibold)).foregroundStyle(Palette.ink)
                Text("/ ?").font(AppFont.numCaption).foregroundStyle(Palette.muted)
                Spacer(minLength: Spacing.s8)
                Text("0%").font(AppFont.numStat).foregroundStyle(Palette.accent)
            }
            .lineLimit(1)
            GoalProgressBar(progress: 0)
            HStack(alignment: .firstTextBaseline) {
                Text("小牛帮你算哪天攒够").font(AppFont.small).foregroundStyle(Palette.muted)
                Spacer(minLength: Spacing.s8)
                if showsButton {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                        Text("定个目标").font(AppFont.ui(12, .bold))
                        PhosphorIcon(.caretRight, size: 11).iconOnTextBaseline(12)
                    }
                    .foregroundStyle(Palette.accent)
                }
            }
            .lineLimit(1)
        }
        .padding(.vertical, Spacing.s14)
        .padding(.horizontal, Spacing.s16)
        .goalCardBackground()
    }
}

/// 面板放不下空状态卡时的一行提示：旗子、「给自己定个目标吧」、右箭头，整行可点，进入目标管理。
private struct EmptyGoalRow: View {
    let prompt: String
    let openGoals: () -> Void

    var body: some View {
        Button(action: openGoals) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                PhosphorIcon(.flagBanner, size: 13).iconOnTextBaseline().foregroundStyle(Palette.accent)
                Text(prompt).font(AppFont.captionSemibold).foregroundStyle(Palette.ink)
                Spacer()
                PhosphorIcon(.caretRight, size: 11).foregroundStyle(Palette.muted)
            }
            .padding(.vertical, Spacing.s2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: Radius.r6, outset: Spacing.s6))
    }
}

/// 目标进度条：高 6，line 底、accent 填充。
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
