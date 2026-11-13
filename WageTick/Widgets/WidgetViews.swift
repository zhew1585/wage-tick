import SwiftUI
import WageCore

/// 桌面小组件的内容 (PRD F14，设计稿「大胆风格 · 桌面小组件」：小号 170×170、中号 364×170、大号 364×382)。
/// 小号、中号整块铺满状态色 (`WidgetBackground`)，大号上半是彩色头图、下半米白底。小牛从右下角冒出来，随场景换姿势。
/// 小组件扩展不打包字体，数字用系统黑体、中文用苹方粗体。内边距在这里给，扩展关掉了系统的内容边距。
struct WidgetContentView: View {
    let snapshot: WidgetSnapshot
    let size: WidgetSize
    let clock: WidgetClock

    var body: some View {
        switch snapshot {
        case .setup(let setup):
            WidgetSetupView(setup: setup, mascotSize: size == .small ? 56 : 72)
                .padding(Spacing.s16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .today(let today):
            let theme = HeroTheme.forWidget(today)
            switch size {
            case .small: SmallWidgetView(today: today, theme: theme, clock: clock)
            case .medium: MediumWidgetView(today: today, theme: theme, clock: clock)
            case .large: LargeWidgetView(today: today, theme: theme, clock: clock)
            }
        }
    }
}

/// 小组件的底色：今天的小号、中号铺满状态渐变，大号与未完成引导是米白底 (大号的彩色头图画在内容里)。
/// 扩展用作 `containerBackground`，离屏预览也铺它。
struct WidgetBackground: View {
    let snapshot: WidgetSnapshot
    let size: WidgetSize

    var body: some View {
        if case .today(let today) = snapshot, size != .large {
            HeroTheme.forWidget(today).gradient
        } else {
            Palette.bg
        }
    }
}

// MARK: 小号

/// 小号：状态胶囊、一句标题、大数字 (休息日为距上班几天)，底部进度格与倒计时；小牛在右下角。
private struct SmallWidgetView: View {
    let today: WidgetToday
    let theme: HeroTheme
    let clock: WidgetClock

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WidgetCowImage(scene: today.scene)
                .frame(width: lying ? 130 : 78, height: lying ? 173 : 104)
                .offset(x: 6, y: lying ? 22 : 14)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                WidgetStatusPill(today: today)
                    .padding(.bottom, Spacing.s8)
                WidgetKicker(text: kicker, theme: theme, size: 12)
                WidgetBigNumber(today: today, theme: theme, size: 38)
                Spacer(minLength: 0)
                if let blocks = today.blocks, !lying {
                    WidgetBlocks(blocks: blocks, theme: theme).frame(width: 84, height: 6)
                        .padding(.bottom, Spacing.s4)
                }
                if !lying {
                    footer
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 已下班的小牛躺在底部，底部那行字就不放了。
    private var lying: Bool { today.scene == .offWork }

    private var kicker: String { WidgetText.kicker(today) }

    @ViewBuilder
    private var footer: some View {
        switch today.main {
        case .amount(let amount):
            WidgetFootText(stat: amount.footer, clock: clock, color: theme.kicker)
        case .rest(let rest):
            if let next = rest.nextAttendanceText {
                Text(next.replacingOccurrences(of: "下个上班日 ", with: ""))
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(theme.kicker).lineLimit(1)
            }
        }
    }
}

// MARK: 中号

/// 中号：左边状态与日期、标题、大数字、进度格与两端时刻；右边小牛，头顶气泡写倒计时。
private struct MediumWidgetView: View {
    let today: WidgetToday
    let theme: HeroTheme
    let clock: WidgetClock

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s8) {
                WidgetStatusPill(today: today)
                Text(today.dateText).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondary)
            }
            .padding(.bottom, Spacing.s8)
            WidgetKicker(text: WidgetText.kicker(today), theme: theme, size: 13)
            WidgetBigNumber(today: today, theme: theme, size: 48)
            Spacer(minLength: 0)
            progress.frame(width: 200, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 小牛与气泡叠在右边，不参与排版 (小牛比小组件还高，底下被裁掉)。
        .overlay(alignment: .topTrailing) {
            let lying = today.scene == .offWork
            WidgetCowImage(scene: today.scene)
                .frame(width: lying ? 150 : 120, height: lying ? 200 : 160)
                .padding(.top, lying ? 0 : 44)
                .offset(y: lying ? -22 : 0)
                .padding(.trailing, Spacing.s4)
        }
        .overlay(alignment: .topTrailing) {
            WidgetBubble(today: today, theme: theme, clock: clock)
                .padding(.top, 14)
                .padding(.trailing, 22)
        }
        .clipped()
    }

    @ViewBuilder
    private var progress: some View {
        if let blocks = today.blocks {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                WidgetBlocks(blocks: blocks, theme: theme).frame(height: 8)
                HStack {
                    if case .amount(let amount) = today.main, let progress = amount.progress {
                        Text(progress.startTime)
                        Spacer()
                        Text(blocks.value)
                        Spacer()
                        Text(progress.endTime)
                    } else {
                        Text(blocks.label)
                        Spacer()
                        Text(blocks.value)
                    }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(theme.kicker)
            }
        } else if let stat = today.stats.first {
            WidgetFootText(stat: stat, clock: clock, color: theme.kicker)
        }
    }
}

// MARK: 大号

/// 大号：上半是缩小的首页头图 (状态、标题、大数字、说明行、小牛与气泡)，下半米白底：进度格、三项统计、当前目标墨色卡。
private struct LargeWidgetView: View {
    let today: WidgetToday
    let theme: HeroTheme
    let clock: WidgetClock

    var body: some View {
        VStack(spacing: 0) {
            hero
            VStack(spacing: Spacing.s12) {
                if let blocks = today.blocks {
                    VStack(spacing: Spacing.s6) {
                        HStack(alignment: .lastTextBaseline) {
                            Text(blocks.label).font(.system(size: 11, weight: .heavy)).foregroundStyle(Palette.ink)
                            Spacer()
                            Text(blocks.value).font(.system(size: 15, weight: .black))
                                .foregroundStyle(blocks.isUnpaid ? Palette.hot : Palette.accent)
                        }
                        WidgetBlocks(blocks: blocks, theme: nil).frame(height: 10)
                    }
                }
                WidgetStatsRow(stats: today.stats, clock: clock)
                Spacer(minLength: 0)
                WidgetGoalCard(goal: today.goal)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
            .frame(maxHeight: .infinity)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s8) {
                WidgetStatusPill(today: today)
                Text(today.dateText).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondary)
            }
            .padding(.bottom, 10)
            WidgetKicker(text: WidgetText.kicker(today), theme: theme, size: 14)
            WidgetBigNumber(today: today, theme: theme, size: 58)
            if let caption = WidgetText.caption(today) {
                Text(caption).font(.system(size: 11, weight: .bold)).foregroundStyle(theme.secondary)
                    .lineLimit(1).frame(maxWidth: 200, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            WidgetCowImage(scene: today.scene)
                .frame(width: 130, height: 173)
                .padding(.top, today.scene == .offWork ? 20 : 46)
                .padding(.trailing, Spacing.s2)
        }
        .overlay(alignment: .topTrailing) {
            WidgetBubble(today: today, theme: theme, clock: clock)
                .padding(.top, 14)
                .padding(.trailing, 22)
        }
        .frame(height: 178)
        .background(theme.gradient)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }
}

// MARK: 小组件里的零件

/// 小组件里的文字：标题、说明行，按状态从快照里取。
private enum WidgetText {
    /// 大数字上方的一句：应出勤日与白干中原样用快照的标签 (今日已赚、今日结算、今日已倒贴)，休息日为「离开工还有」。
    static func kicker(_ today: WidgetToday) -> String {
        switch today.main {
        case .amount(let amount): amount.label
        case .rest(let rest): rest.daysUntilWork == nil ? rest.headline : "离开工还有"
        }
    }

    static func caption(_ today: WidgetToday) -> String? {
        switch today.main {
        case .amount(let amount): amount.caption
        case .rest(let rest): rest.nextAttendanceText
        }
    }
}

/// 状态胶囊：墨色底白字 (白干中红底)，前面一个亮色圆点。
private struct WidgetStatusPill: View {
    let today: WidgetToday

    var body: some View {
        HStack(spacing: Spacing.s4) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text(today.statusLabel).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
        }
        .padding(.horizontal, Spacing.s8)
        .padding(.vertical, 3)
        .background(today.tone == .unpaidWork ? Palette.hot : Palette.ink, in: Capsule())
    }

    private var dot: Color {
        switch today.tone {
        case .unpaidWork: .white
        case .rest: Palette.highlight
        case .attendance:
            switch today.scene {
            case .working, .paydaySoon, .payday: Palette.lime
            case .offWork: Color(hex: 0x8CE99A)
            default: Palette.highlight
            }
        }
    }
}

private struct WidgetKicker: View {
    let text: String
    let theme: HeroTheme
    let size: CGFloat

    var body: some View {
        Text(text).font(.system(size: size, weight: .heavy)).foregroundStyle(theme.kicker).lineLimit(1)
    }
}

/// 大数字：¥ + 整数 (系统黑体) + 小数；休息日为天数 + 「天」。
private struct WidgetBigNumber: View {
    let today: WidgetToday
    let theme: HeroTheme
    let size: CGFloat

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 1) {
            switch today.main {
            case .amount(let amount):
                let parts = Self.split(amount.amount)
                Text("¥").font(.system(size: size * 0.42, weight: .black)).foregroundStyle(theme.kicker)
                Text(parts.integer).font(.system(size: size, weight: .black)).tracking(-size * 0.04).foregroundStyle(theme.number)
                if let decimals = parts.decimals {
                    Text("." + decimals).font(.system(size: size * 0.42, weight: .black)).foregroundStyle(theme.number)
                }
            case .rest(let rest):
                Text(rest.daysUntilWork.map(String.init) ?? "-")
                    .font(.system(size: size * 1.15, weight: .black)).foregroundStyle(theme.number)
                if rest.daysUntilWork != nil {
                    Text("天").font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(theme.kicker)
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// 「571.43」拆成 571 与 43。
    private static func split(_ amount: String) -> (integer: String, decimals: String?) {
        let parts = amount.split(separator: ".", maxSplits: 1).map(String.init)
        return (parts.first ?? amount, parts.count > 1 ? parts[1] : nil)
    }
}

/// 每小时一格的进度格 (同面板 `HourBlocksView`)。`theme` 为 nil 时画在米白底上 (大号下半)，否则画在彩色底上。
private struct WidgetBlocks: View {
    let blocks: HourBlocks
    let theme: HeroTheme?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<blocks.count, id: \.self) { index in
                let fill = min(max(blocks.filled - Double(index), 0), 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(empty)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Rectangle().fill(filled).frame(width: geometry.size.width * fill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            if blocks.overtime {
                RoundedRectangle(cornerRadius: 2).fill(Palette.hot)
            }
        }
    }

    private var filled: Color {
        if blocks.isUnpaid && !blocks.overtime { return Palette.hot }
        if let theme, theme == .night { return .white }
        return Palette.ink
    }

    private var empty: Color {
        guard let theme else { return Palette.surface }
        return theme == .sun ? Palette.ink.opacity(0.15) : .white.opacity(0.3)
    }
}

/// 一行底部小字：「距下班 3:00:00」，计时由系统实时走。
private struct WidgetFootText: View {
    let stat: WidgetStat
    let clock: WidgetClock
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.s4) {
            Text(stat.title.replacingOccurrences(of: "距离", with: "距"))
            if let value = stat.value {
                clock.text(value).monospacedDigit()
            }
        }
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// 头顶白色气泡：应出勤日写倒计时 (底部那项)，白干中写已白干，休息日写距上班几天。
private struct WidgetBubble: View {
    let today: WidgetToday
    let theme: HeroTheme
    let clock: WidgetClock

    var body: some View {
        if let content {
            VStack(alignment: .leading, spacing: 0) {
                if let label = content.label {
                    Text(label).font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
                content.value
                    .font(.system(size: 15, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(theme.bubbleAccent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12))
        }
    }

    private var content: (label: String?, value: Text)? {
        switch today.main {
        case .amount(let amount):
            // 未上班时没有倒计时 (值是「-」)，气泡就不出来。
            guard let value = amount.footer.value, value != .text("-") else { return nil }
            let title = amount.footer.title.replacingOccurrences(of: "距离", with: "距")
            if case .elapsed = value { return ("已白干", clock.text(value)) }
            return (title, clock.text(value))
        case .rest(let rest):
            guard let days = rest.daysUntilWork else { return nil }
            return ("距上班", Text(days == 1 ? "明天" : "\(days) 天"))
        }
    }
}

/// 大号的三项统计：居中，数值系统黑体 15，标题 9 muted，中间细竖线。
private struct WidgetStatsRow: View {
    let stats: [WidgetStat]
    let clock: WidgetClock

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 { Rectangle().fill(Palette.line).frame(width: 1, height: 26) }
                VStack(spacing: 1) {
                    Group {
                        if let value = stat.value { clock.text(value) } else { Text("-") }
                    }
                    .font(.system(size: 15, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(color(stat))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Text(stat.title).font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(_ stat: WidgetStat) -> Color {
        if case .text(let text) = stat.value, text.hasPrefix("−") { return Palette.loss }
        if stat.isHighlighted { return Palette.accent }
        if stat.title == "本月累计" { return Palette.money }
        return Palette.ink
    }
}

/// 大号底部的当前目标：墨色卡，黄色「正在攒」、名称、橙色百分比、渐变进度条、预计。没有目标时一行淡淡的提示。
private struct WidgetGoalCard: View {
    let goal: GoalCard

    var body: some View {
        switch goal {
        case .empty(let prompt):
            WidgetEmptyGoal(prompt: prompt)
        case .active(let goal):
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack(spacing: 5) {
                    Text("正在攒").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Palette.highlight, in: RoundedRectangle(cornerRadius: 4))
                    Text(goal.name).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: Spacing.s4)
                    Text(goal.percentText).font(.system(size: 17, weight: .black)).foregroundStyle(Color(hex: 0xFF7A2E))
                }
                GeometryReader { geometry in
                    Capsule().fill(.white.opacity(0.12)).overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.highlight, Color(hex: 0xFF7A2E)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * min(max(goal.progress, 0), 1))
                    }
                }
                .frame(height: 6)
                Text(goal.estimate).font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// 小组件里的小牛：按场景取一张整只的静态图 (扩展里不放动画)。
private struct WidgetCowImage: View {
    let scene: CowScene

    var body: some View {
        Image(Self.name(scene)).resizable().scaledToFit().accessibilityHidden(true)
    }

    private static func name(_ scene: CowScene) -> String {
        switch scene.pose {
        case .yawning: "WidgetCowYawning"
        case .working: "WidgetCowWorking"
        case .eating: "WidgetCowEating"
        case .lyingFlat: "WidgetCowLyingFlat"
        case .sunbathing: "WidgetCowSunbathing"
        case .sweating: "WidgetCowSweating"
        case .excited: "WidgetCowExcited"
        case .paid: "WidgetCowPaid"
        }
    }
}
