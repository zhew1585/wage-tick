import SwiftUI
import WageCore

/// 面板目标区「攒钱队列」(PRD F9，设计稿「首页 · 大胆版」)：文字和进度原样取自快照的 `GoalCard`、`GoalQueueSection`。
/// 累计中目标是一张墨色大卡 (`BoldGoalCard`)，下面排队中的目标缩成并排的小胶囊 (与累计中合计最多 3 个)。
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
                .buttonStyle(.highlight(radius: Radius.r18))
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

/// 累计中目标的墨色大卡 (设计稿「大胆版」Goal Card)：左上黄色「正在攒」标签与名称，右上目标总数 (或队列位置)；
/// 中间累计额 (Archivo Black 24) + 「/ 目标金额」，右侧橙色大百分比；下面黄到橙的渐变进度条，最下一行预计。
/// 目标页 (`GoalsView`) 也用这张卡。
struct BoldGoalCard: View {
    let goal: ActiveGoalCard
    /// 右上角的小字，如「3 个目标」「队列 1/4」。
    var trailing: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            HStack(spacing: Spacing.s6) {
                Text("正在攒")
                    .font(AppFont.ui(10, .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Spacing.s6)
                    .padding(.vertical, Spacing.s2)
                    .background(Palette.highlight, in: RoundedRectangle(cornerRadius: Radius.r5))
                Text(goal.name).font(AppFont.ui(15, .bold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: Spacing.s8)
                if let trailing {
                    Text(trailing).font(AppFont.num(11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
                Text(BoldNumber.grouped(goal.accumulatedText)).font(AppFont.heavy(24)).foregroundStyle(.white)
                Text("/ \(BoldNumber.grouped(goal.targetText).replacingOccurrences(of: "¥", with: ""))")
                    .font(AppFont.num(12)).foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: Spacing.s8)
                Text("\(Int((goal.progress * 100).rounded(.down)))%").font(AppFont.heavy(28)).foregroundStyle(Color(hex: 0xFF7A2E))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            GoalProgressBar(progress: goal.progress)
            Text(goal.estimate).font(AppFont.small).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
        }
        .padding(.vertical, Spacing.s14)
        .padding(.horizontal, Spacing.s16)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: Radius.r18))
    }
}

/// 排队中目标缩成并排的小胶囊：surface 底，名称 12/700，右侧短版预计。悬停显示完整预计。
private struct QueuedGoalChips: View {
    let goals: [QueuedGoalCard]

    var body: some View {
        HStack(spacing: Spacing.s8) {
            ForEach(goals) { goal in
                HStack(spacing: Spacing.s6) {
                    Text(goal.name).font(AppFont.ui(12, .bold)).foregroundStyle(Palette.ink)
                    Spacer(minLength: Spacing.s4)
                    Text(goal.shortEstimate).font(AppFont.num(10)).foregroundStyle(Palette.muted)
                }
                .lineLimit(1)
                .padding(.horizontal, Spacing.s12)
                .padding(.vertical, Spacing.s8)
                .frame(maxWidth: .infinity)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r12))
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

/// 目标进度条：高 8，半透明白底、黄到橙渐变填充 (放在墨色卡上)。
private struct GoalProgressBar: View {
    /// 进度条比例，0 至 1。
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.white.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.highlight, Color(hex: 0xFF7A2E)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: 8)
    }
}
