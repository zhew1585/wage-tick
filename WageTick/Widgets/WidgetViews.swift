import SwiftUI
import WageCore

/// 桌面小组件的内容 (PRD F14，设计稿 uRf1y：小号 170×170、中号 364×170、大号 364×382)。
/// 底色由外面给 (桌面上是 `containerBackground`，预览里自己铺)；内边距在这里，扩展关掉了系统的内容边距。
struct WidgetContentView: View {
    let snapshot: WidgetSnapshot
    let size: WidgetSize
    let clock: WidgetClock

    var body: some View {
        Group {
            switch snapshot {
            case .setup(let setup):
                WidgetSetupView(setup: setup, mascotSize: size == .small ? 56 : 72)
            case .today(let today):
                switch size {
                case .small: SmallWidgetView(today: today, clock: clock)
                case .medium: MediumWidgetView(today: today, clock: clock)
                case .large: LargeWidgetView(today: today, clock: clock)
                }
            }
        }
        .padding(.vertical, Spacing.s16)
        .padding(.horizontal, size == .large ? Spacing.s18 : Spacing.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: 小号

/// 小号：牛头与状态；大数字贴底，下面进度条与距离下班 (白干中为开始时刻与计时，已下班为一句小结)。
/// 休息日为居中的小牛、「今天休息」与下个上班日。
private struct SmallWidgetView: View {
    let today: WidgetToday
    let clock: WidgetClock

    var body: some View {
        switch today.main {
        case .amount(let amount):
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(glyphSize: 18, statusLabel: today.statusLabel, tone: today.tone)
                Spacer(minLength: 0)
                WidgetAmountView(label: amount.label, amount: amount.amount, amountSize: amount.amountSize)
                if let progress = amount.progress {
                    WidgetBar(ratio: progress.ratio).padding(.top, Spacing.s14)
                    WidgetFootRow(stat: amount.footer, clock: clock).padding(.top, Spacing.s10)
                } else {
                    WidgetFootRow(stat: amount.footer, clock: clock, valueColor: today.tone.color).padding(.top, Spacing.s16)
                }
            }
        case .rest(let rest):
            VStack(spacing: Spacing.s6) {
                WidgetMascot(size: 64)
                Text(rest.headline).font(AppFont.ui(17, .bold)).foregroundStyle(Palette.ink)
                if let next = rest.nextAttendanceText {
                    Text(next).font(AppFont.ui(10)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: 中号

/// 中号：左栏同小号 (进度条下方标出上下班与百分比)，竖线右边两项统计与累计中目标。
private struct MediumWidgetView: View {
    let today: WidgetToday
    let clock: WidgetClock

    var body: some View {
        HStack(spacing: Spacing.s16) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(glyphSize: 18, dateText: today.dateText, statusLabel: today.statusLabel, tone: today.tone)
                Spacer(minLength: 0)
                left
                // 休息日、请假全天只有小牛与两行字，放在标题下方的剩余空间正中，不沉底，免得上面空出一大块。
                if case .rest = today.main {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: Spacing.s10) {
                ForEach(Array(today.sideStats.enumerated()), id: \.offset) { _, stat in
                    WidgetStatView(stat: stat, clock: clock)
                }
                MediumGoalView(goal: today.goal)
            }
            .frame(width: 140)
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var left: some View {
        switch today.main {
        case .amount(let amount):
            WidgetAmountView(label: amount.label, amount: amount.amount, amountSize: amount.amountSize)
            if let progress = amount.progress {
                WidgetBar(ratio: progress.ratio).padding(.top, Spacing.s14)
                WidgetTicks(start: progress.startTime, percent: progress.percent, end: progress.endTime).padding(.top, Spacing.s8)
            } else {
                WidgetFootRow(stat: amount.footer, clock: clock, valueColor: today.tone.color).padding(.top, Spacing.s16)
            }
        case .rest(let rest):
            // 左栏只有 160 宽，下个上班日放不进小牛右边，单独一行。
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack(spacing: Spacing.s8) {
                    WidgetMascot(size: 56)
                    Text(rest.headline).font(AppFont.ui(17, .bold)).foregroundStyle(Palette.ink)
                }
                if let next = rest.nextAttendanceText {
                    Text(next).font(AppFont.ui(10)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
    }
}

/// 中号右栏的目标：旗子 11、名称 11/600、右侧百分比 10/600，下面 4pt 进度条；没有目标时一行提示。
private struct MediumGoalView: View {
    let goal: GoalCard

    var body: some View {
        switch goal {
        case .empty(let prompt):
            WidgetEmptyGoal(prompt: prompt)
        case .active(let goal):
            VStack(spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                    PhosphorIcon(.flagBanner, size: 11).iconOnTextBaseline().foregroundStyle(Palette.accent)
                    Text(goal.name).font(AppFont.ui(11, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Spacer(minLength: Spacing.s4)
                    Text(goal.percentText).font(AppFont.num(10, .semibold)).foregroundStyle(Palette.accent)
                }
                WidgetBar(ratio: goal.progress, height: 4, color: Palette.accent)
            }
        }
    }
}

// MARK: 大号

/// 大号：顶部牛头、日期与状态；主数字与小字；分段进度条与上下班、百分比；三项统计；底部攒钱队列 (累计中卡片 + 最多 2 个排队中)。
/// 休息日主数字换成小牛与下个上班日；已下班、白干中没有进度条，主数字放大。统计行中间一项是距离周末。
private struct LargeWidgetView: View {
    let today: WidgetToday
    let clock: WidgetClock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(glyphSize: 20, dateText: today.dateText, dateSize: 11, statusLabel: today.statusLabel, tone: today.tone)
            // 剩余高度平分到三处间距：休息日、没有进度条、排队中目标少时内容变矮，空白不全堆在统计与目标之间。
            Spacer(minLength: Spacing.s10)
            main
            Spacer(minLength: Spacing.s10)
            stats
            Spacer(minLength: Spacing.s8)
            LargeGoalsView(goal: today.goal, queued: today.queued)
        }
    }

    @ViewBuilder
    private var main: some View {
        switch today.main {
        case .amount(let amount):
            VStack(alignment: .leading, spacing: 0) {
                // 没有进度条 (已下班、白干中) 时少两行，主数字放大到 46，免得统计行下面空出一大块 (设计稿「距离周末 · 方案 B」)。
                let large = amount.progress == nil
                WidgetAmountView(
                    label: amount.label, amount: amount.amount,
                    labelSize: 12, currencySize: large ? 20 : 16, amountSize: large ? 46 : 36
                )
                caption(amount)
                if let progress = amount.progress {
                    WidgetSegmentedBar(segments: progress.segments).padding(.top, Spacing.s10)
                    WidgetTicks(start: progress.startText, percent: progress.percent, end: progress.endText).padding(.top, Spacing.s6)
                }
            }
        case .rest(let rest):
            // 休息日、全天请假：小牛 84、标题 22、下个上班日 12，撑起上半部分。
            HStack(spacing: Spacing.s14) {
                WidgetMascot(size: 84)
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    Text(rest.headline).font(AppFont.ui(22, .bold)).foregroundStyle(Palette.ink)
                    if let next = rest.nextAttendanceText {
                        Text(next).font(AppFont.ui(12)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
            }
        }
    }

    /// 主数字下方的小字 (11 muted)；白干中后面接已白干计时 (loss)。
    private func caption(_ amount: WidgetAmount) -> some View {
        var text = Text(amount.caption)
        if let timer = amount.captionTimer {
            // 拼成一段文字，计时不会把小字撑开到整行宽。
            text = text + Text(" ") + clock.text(timer).font(AppFont.num(11, .semibold)).foregroundColor(today.tone.color)
        }
        return text.font(AppFont.ui(11)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.8)
    }

    /// 统计行：各项平分宽度，项与项之间 1×28 竖线，数值 14/600。
    private var stats: some View {
        HStack(spacing: Spacing.s8) {
            ForEach(Array(today.stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle().fill(Palette.line).frame(width: 1, height: 28)
                }
                WidgetStatView(stat: stat, clock: clock, valueSize: 14)
            }
        }
    }
}

/// 大号底部的攒钱队列：累计中卡片 (accent-soft、圆角 12) 与排队中目标各一行 (高 26，行间细线)；没有目标时一行提示。
private struct LargeGoalsView: View {
    let goal: GoalCard
    let queued: [QueuedGoalCard]

    var body: some View {
        switch goal {
        case .empty(let prompt):
            WidgetEmptyGoal(prompt: prompt)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s12)
                .padding(.vertical, Spacing.s10)
                .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Palette.line))
        case .active(let active):
            VStack(spacing: 0) {
                card(active)
                ForEach(Array(queued.enumerated()), id: \.element.id) { index, goal in
                    if index > 0 { Palette.line.frame(height: 1) }
                    row(goal)
                }
            }
        }
    }

    /// 第一行旗子 13、名称 13/600、百分比 12/600；第二行累计额 16/600、「/ 目标金额」11、右侧短版预计 10；最下面 5pt 进度条。
    private func card(_ goal: ActiveGoalCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                PhosphorIcon(.flagBanner, size: 13).iconOnTextBaseline().foregroundStyle(Palette.accent)
                Text(goal.name).font(AppFont.ui(13, .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: Spacing.s8)
                Text(goal.percentText).font(AppFont.num(12, .semibold)).foregroundStyle(Palette.accent)
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
                Text(goal.accumulatedText).font(AppFont.num(16, .semibold)).foregroundStyle(Palette.ink)
                Text("/ \(goal.targetText)").font(AppFont.num(11)).foregroundStyle(Palette.muted)
                Spacer(minLength: Spacing.s8)
                Text(goal.shortEstimate).font(AppFont.ui(10)).foregroundStyle(Palette.muted)
            }
            .lineLimit(1)
            WidgetBar(ratio: goal.progress, height: 5, color: Palette.accent)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, Spacing.s12)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    /// 排队中一行：沙漏 11、名称 11/500，右侧目标金额 (等宽 11) 与短版预计 11 muted，按基线对齐。
    private func row(_ goal: QueuedGoalCard) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            PhosphorIcon(.hourglassSimple, size: 11).iconOnTextBaseline().foregroundStyle(Palette.muted)
            Text(goal.name).font(AppFont.ui(11, .medium)).foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.s8)
            Text(goal.amountText).font(AppFont.num(11)).foregroundStyle(Palette.ink)
            Text(goal.shortEstimate).font(AppFont.ui(11)).foregroundStyle(Palette.muted)
        }
        .lineLimit(1)
        .padding(.horizontal, Spacing.s2)
        .frame(height: 26)
    }
}

private extension WidgetAmount {
    /// 小号、中号的大数字字号：没有进度条 (白干中、已下班、请假全天) 时少一行，放大到 36 并拉开与下一行的距离，免得上面空出一大块。
    var amountSize: CGFloat { progress == nil ? 36 : 30 }
}
