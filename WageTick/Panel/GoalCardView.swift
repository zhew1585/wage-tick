import SwiftUI
import WageCore

/// 面板目标区「攒钱队列」(PRD F9，设计稿 P2 Goals · 760)：文字和进度原样取自快照的 `GoalCard`、`GoalQueueSection`。
/// 标题行「攒钱队列」+ 右侧目标总数；下面直接列出累计中目标与排队中目标 (与累计中合计最多 3 个)，不再展开收起。
/// 累计中目标一行：旗子图标、名称、预计完成，下方 4pt 进度条；排队中目标图标换成沙漏、整行 muted、进度条为空。
/// 队列为空时标题下是「给自己定个目标吧」，整行可点，进入目标管理。
struct GoalCardView: View {
    let card: GoalCard
    /// 排队部分；没有排队中目标时为 nil。只用 `upcoming`，旧的展开收起 (`queued`、`toggleTitle`) 不再用。
    let queue: GoalQueueSection?
    /// 标题右侧的目标总数，如「3 个目标」；队列为空时为 nil。
    let countText: String?
    let openGoals: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s16) {
            header
            mainRow
            ForEach(queue?.upcoming ?? []) { goal in
                GoalRowView(icon: .hourglassSimple, name: goal.name, estimate: goal.estimate, progress: 0, muted: true)
                    .help(goal.amountText)
            }
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s18)
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

    @ViewBuilder
    private var mainRow: some View {
        switch card {
        case .empty(let prompt):
            Button(action: openGoals) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                    PhosphorIcon(.flagBanner, size: 13).iconOnTextBaseline()
                    Text(prompt).font(AppFont.captionSemibold)
                    Spacer()
                    PhosphorIcon(.caretRight, size: 11)
                }
                .foregroundStyle(Palette.muted)
                .padding(.vertical, Spacing.s2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.highlight(radius: Radius.r6, outset: Spacing.s6))
        case .active(let goal):
            // 设计稿不展示金额，悬停时显示「¥3000 / ¥10000」。
            GoalRowView(icon: .flagBanner, name: goal.name, estimate: goal.estimate, progress: goal.progress, muted: false)
                .help(goal.amountText)
        }
    }
}

/// 目标区的一行：图标 13、名称 12/600、右侧预计 11，下方 4pt 进度条，间距 7。
private struct GoalRowView: View {
    let icon: Phosphor
    let name: String
    let estimate: String
    /// 进度条比例，0 至 1。
    let progress: Double
    /// 排队中：图标与名称都用 muted。
    let muted: Bool

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                PhosphorIcon(icon, size: 13).iconOnTextBaseline().foregroundStyle(muted ? Palette.muted : Palette.accent)
                Text(name)
                    .font(AppFont.captionSemibold)
                    .foregroundStyle(muted ? Palette.muted : Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Spacing.s8)
                Text(estimate).font(AppFont.small).foregroundStyle(Palette.muted).lineLimit(1)
            }
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: Radius.r2)
                    .fill(Palette.line)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Radius.r2)
                            .fill(Palette.accent)
                            .frame(width: geometry.size.width * min(max(progress, 0), 1))
                    }
            }
            .frame(height: 4)
        }
    }
}
