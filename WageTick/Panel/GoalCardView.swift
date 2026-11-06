import SwiftUI
import WageCore

/// 面板目标区「攒钱队列」(PRD F9，设计稿 P2 面板 · 上班中 · 攒钱队列改版 · 760)：文字和进度原样取自快照的 `GoalCard`、`GoalQueueSection`。
/// 标题行「攒钱队列」+ 右侧目标总数；下面是累计中目标的卡片，再下面是排队中目标的紧凑列表 (与累计中合计最多 3 个)。
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
        VStack(spacing: Spacing.s12) {
            header
            switch card {
            case .empty(let prompt):
                switch density {
                case .full: EmptyGoalCard(prompt: prompt, showsButton: true, openGoals: openGoals)
                case .oneQueued: EmptyGoalCard(prompt: prompt, showsButton: false, openGoals: openGoals)
                case .minimal: EmptyGoalRow(prompt: prompt, openGoals: openGoals)
                }
            case .active(let goal):
                ActiveGoalCardView(goal: goal)
                let upcoming = (queue?.upcoming ?? []).prefix(density.queuedLimit)
                if !upcoming.isEmpty {
                    QueuedGoalList(goals: Array(upcoming))
                }
            }
        }
        .padding(EdgeInsets(top: Spacing.s14, leading: Spacing.screen, bottom: Spacing.s10, trailing: Spacing.screen))
    }

    private var header: some View {
        HStack {
            Text("攒钱队列").font(AppFont.captionSemibold)
            Spacer()
            if let countText {
                Text(countText).font(AppFont.small)
            }
        }
        .foregroundStyle(Palette.muted)
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

/// 累计中目标的卡片：accent-soft 底、圆角 12。
/// 第一行旗子、名称 14/600、右侧百分比；第二行累计额 20/600 + 「/ 目标金额」、右侧短版预计；最下面 6pt 进度条。
private struct ActiveGoalCardView: View {
    let goal: ActiveGoalCard

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                PhosphorIcon(.flagBanner, size: 14).iconOnTextBaseline().foregroundStyle(Palette.accent)
                Text(goal.name).font(AppFont.section).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: Spacing.s8)
                Text(goal.percentText).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
                Text(goal.accumulatedText).font(AppFont.num(20, .semibold)).foregroundStyle(Palette.ink)
                Text("/ \(goal.targetText)").font(AppFont.numCaption).foregroundStyle(Palette.muted)
                Spacer(minLength: Spacing.s8)
                Text(goal.shortEstimate).font(AppFont.small).foregroundStyle(Palette.muted)
            }
            .lineLimit(1)
            GoalProgressBar(progress: goal.progress)
        }
        .padding(.vertical, Spacing.s12)
        .padding(.horizontal, Spacing.s14)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.card))
    }
}

/// 排队中目标：每行高 32，沙漏、名称 13/500，右侧目标金额与短版预计，行间细线。悬停显示完整预计。
private struct QueuedGoalList: View {
    let goals: [QueuedGoalCard]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(goals.enumerated()), id: \.element.id) { index, goal in
                if index > 0 { Palette.line.frame(height: 1) }
                HStack(spacing: Spacing.s8) {
                    PhosphorIcon(.hourglassSimple, size: 13).foregroundStyle(Palette.muted)
                    Text(goal.name).font(AppFont.bodyMedium).foregroundStyle(Palette.ink)
                    Spacer(minLength: Spacing.s8)
                    Text(goal.amountText).font(AppFont.numCaption).foregroundStyle(Palette.ink)
                    Text(goal.shortEstimate).font(AppFont.small).foregroundStyle(Palette.muted)
                }
                .lineLimit(1)
                .padding(.horizontal, Spacing.s4)
                .frame(height: 32)
                .help(goal.estimate)
            }
        }
    }
}

/// 队列为空：描边卡片居中放旗子 30、提示 14/600、小字 11 和「新目标」次要按钮。
/// 不带按钮时 (面板放不下) 整张卡可点。两种都进入目标管理。
private struct EmptyGoalCard: View {
    let prompt: String
    let showsButton: Bool
    let openGoals: () -> Void

    var body: some View {
        if showsButton {
            card
        } else {
            Button(action: openGoals) { card.contentShape(Rectangle()) }
                .buttonStyle(.highlight(radius: Radius.card))
        }
    }

    private var card: some View {
        VStack(spacing: Spacing.s8) {
            PhosphorIcon(.flagBanner, size: 30).foregroundStyle(Palette.accent)
            Text(prompt).font(AppFont.section).foregroundStyle(Palette.ink)
            Text("攒够了，给你放烟花").font(AppFont.small).foregroundStyle(Palette.muted)
            if showsButton {
                Button(action: openGoals) { Label { Text("新目标") } icon: { PhosphorIcon(.plus) } }
                    .buttonStyle(.secondary(fullWidth: true, height: 34))
                    .frame(width: 120)
                    .padding(.top, Spacing.s4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: Spacing.s18, leading: Spacing.screen, bottom: Spacing.s16, trailing: Spacing.screen))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.line))
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
