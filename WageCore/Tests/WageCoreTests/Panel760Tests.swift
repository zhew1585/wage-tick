import Foundation
import Testing
import WageCore

// 今日概览面板与扣钱、请假表单按 760 设计稿 (P2、F5、F6 · 760) 需要的快照字段。
// 标准算例：2026 年 2 月 20 个应出勤日，月薪 20000，日薪 1000，作息 10:00 至 18:00、饭点 12:00 至 13:00。

/// 在 `now` 时刻依次执行命令，返回新状态。
private func sending(_ commands: [Command], to state: AppState, at now: Moment) throws -> AppState {
    try commands.reduce(state) { try apply($1, to: $0, at: now).state }
}

private func panel(_ state: AppState, at now: Moment) throws -> TodayPanel {
    try #require(snapshot(of: state, at: now).panel)
}

@Suite("今日概览 760：顶部与主数字")
struct Panel760HeroTests {
    @Test("顶部时间带秒，如 15:07:30")
    func timeWithSeconds() throws {
        #expect(try panel(try onboarded(), at: standardDay(15, 7, 30)).timeText == "15:07:30")
    }

    @Test("上班中主数字下方为满勤日薪与时薪 (时薪 = 日薪 ÷ 标准工时)")
    func wageCaption() throws {
        #expect(try attendancePanel(try onboarded(), at: standardDay(15, 0)).caption == "满勤日薪 ¥1000 · 时薪 ¥142.86")
    }

    @Test("请后半天后仍显示满勤日薪与按标准工时的时薪，不随今日上限变化")
    func wageCaptionIgnoresLeave() throws {
        let state = try sending([.setLeave(secondHalfLeave(50))], to: try onboarded(), at: standardDay(9, 0))

        #expect(try attendancePanel(state, at: standardDay(11, 0)).caption.hasPrefix("满勤日薪 ¥1000 · 时薪 ¥142.86 · 扣款 "))
    }

    @Test("白干计时中主数字下方为开始时刻与已白干时长")
    func unpaidWorkCaption() throws {
        let state = try sending([.startUnpaidWork], to: try onboarded(), at: standardDay(18, 0))
        let body = try panel(state, at: standardDay(19, 5, 12)).body
        guard case .unpaidWork(let unpaidWork) = body else {
            Issue.record("期望白干计时中面板，实际为 \(body)")
            return
        }

        #expect(unpaidWork.caption == "18:00 起 · 已白干 1:05:12")
    }
}

@Suite("今日概览 760：进度区与统计行")
struct Panel760ProgressTests {
    @Test("进度条下方标出计划上班与下班")
    func progressTicks() throws {
        let progress = try #require(try attendancePanel(try onboarded(), at: standardDay(15, 0)).progress)

        #expect(progress.startText == "上班 10:00")
        #expect(progress.endText == "下班 18:00")
    }

    @Test("请后半天后进度条两端为当日计划：10:00 至 12:00")
    func progressTicksFollowLeave() throws {
        let state = try sending([.setLeave(secondHalfLeave(50))], to: try onboarded(), at: standardDay(9, 0))
        let progress = try #require(try attendancePanel(state, at: standardDay(11, 0)).progress)

        #expect([progress.startText, progress.endText] == ["上班 10:00", "下班 12:00"])
    }

    @Test("统计行中间一项是距离周末 (V1.13 起替代今日扣款)")
    func middleStatIsWeekend() throws {
        let stats = try attendancePanel(try onboarded(), at: standardDay(15, 0)).stats

        #expect(stats.map(\.title) == ["距离下班", "距离周末", "本月累计"])
    }
}

@Suite("今日概览 760：休息日")
struct Panel760RestTests {
    @Test("周六：统计行为本月已上班 (已上班 / 应出勤)、本月累计与距离周末，标题下两行小字为说明与下一个上班日")
    func saturday() throws {
        let body = try panel(try onboarded(), at: moment(2026, 2, 14, 11, 0)).body

        #expect(body == .rest(RestPanel(
            headline: "今天休息",
            tagline: "不搬砖，不计钱。",
            nextAttendanceText: "下一个上班日 2月16日 周一",
            stats: [
                StatItem(title: "本月已上班", value: "10/20 天"),
                StatItem(title: "本月累计", value: "¥10000"),
                StatItem(title: "距离周末", value: "正在休息", tone: .accent),
            ]
        )))
    }

    @Test("全天请假：标题为今天请假，没有「不计钱」的说明 (请假可能扣薪)")
    func fullDayLeaveHeadline() throws {
        let state = try sending([.setLeave(fullDayLeave(100))], to: try onboarded(), at: standardDay(9, 0))
        guard case .rest(let rest) = try panel(state, at: standardDay(11, 0)).body else {
            Issue.record("全天请假应按休息日呈现")
            return
        }

        #expect(rest.headline == "今天请假")
        #expect(rest.tagline == nil)
        #expect(rest.nextAttendanceText == "下一个上班日 2月12日 周四")
    }
}

@Suite("今日概览 760：攒钱队列")
struct Panel760GoalTests {
    private func threeGoals() throws -> AppState {
        try sending(
            [.createGoal(name: "A", amount: 10000), .createGoal(name: "B", amount: 3000), .createGoal(name: "C", amount: 2500)],
            to: try onboarded(), at: standardDay(9, 0)
        )
    }

    @Test("不论展开与否，排队中目标都直接列出 (与累计中合计最多 3 个)，标题右侧为目标总数")
    func listsQueueWithoutExpanding() throws {
        let panel = try panel(try threeGoals(), at: standardDay(11, 0))
        let queue = try #require(panel.goalQueue)

        #expect(queue.upcoming.map { [$0.name, $0.estimate] } == [
            ["B", "排队中 · 预计 2月27日"],
            ["C", "排队中 · 预计 3月4日"],
        ])
        #expect(panel.goalCountText == "3 个目标")
        // 旧的展开状态字段保留：收起时 `queued` 仍为空。
        #expect(queue.queued == [])
    }

    @Test("排队中超过 2 个时只列前 2 个，总数仍按全部目标")
    func upcomingLimit() throws {
        let state = try sending([.createGoal(name: "D", amount: 100), .createGoal(name: "E", amount: 100)], to: try threeGoals(), at: standardDay(9, 0))
        let panel = try panel(state, at: standardDay(11, 0))

        #expect(panel.goalQueue?.upcoming.map(\.name) == ["B", "C"])
        #expect(panel.goalCountText == "5 个目标")
    }

    @Test("只有 1 个目标：没有排队部分，总数 1 个目标；没有目标时没有总数")
    func countWithoutQueue() throws {
        let one = try sending([.createGoal(name: "A", amount: 10000)], to: try onboarded(), at: standardDay(9, 0))

        #expect(try panel(one, at: standardDay(11, 0)).goalCountText == "1 个目标")
        #expect(try panel(try onboarded(), at: standardDay(11, 0)).goalCountText == nil)
    }
}

@Suite("扣钱表单 760：按日薪百分比的折算")
struct Panel760DeductionTests {
    @Test("预览标题：按日薪 10% 时前面加「扣 ¥100 ·」，日薪 20000 ÷ 21 时按完整精度折算后截掉末尾 0；按金额时只有收入项标题")
    func previewTitle() throws {
        let feb = try #require(try panel(try onboarded(), at: standardDay(15, 0)).deductionEntry)
        let may = try #require(try panel(try onboarded(), at: moment(2026, 5, 6, 15, 0)).deductionEntry)

        #expect(feb.previewTitle(.percentOfDailyWage(10)) == "扣 ¥100 · 今日上限")
        #expect(may.previewTitle(.percentOfDailyWage(10)) == "扣 ¥95.24 · 今日上限")
        #expect(feb.previewTitle(.fixed(50)) == "今日上限")
    }

    @Test("这一笔扣多少：按金额原样，按日薪百分比按当月日薪折算 (表单头图与保存按钮用)")
    func amountText() throws {
        let feb = try #require(try panel(try onboarded(), at: standardDay(15, 0)).deductionEntry)
        let may = try #require(try panel(try onboarded(), at: moment(2026, 5, 6, 15, 0)).deductionEntry)

        #expect(feb.amountText(.fixed(50)) == "−¥50")
        #expect(feb.amountText(.percentOfDailyWage(10)) == "−¥100")
        #expect(may.amountText(.percentOfDailyWage(10)) == "−¥95.24")
    }
}
