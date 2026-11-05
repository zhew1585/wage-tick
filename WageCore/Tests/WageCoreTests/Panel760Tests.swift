import Foundation
import Testing
import WageCore

// 今日概览面板与扣钱、请假表单按 760 设计稿 (P2、F5、F6 · 760) 需要的快照字段。
// 标准算例：2026 年 2 月 20 个应出勤日，月薪 20000，日薪 1000，作息 10:00 至 18:00、午休 12:00 至 13:00。

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
        #expect(try attendancePanel(try onboarded(), at: standardDay(15, 0)).caption == "满勤日薪 ¥1000 · 时薪 ¥142.8571")
    }

    @Test("请下午假后仍显示满勤日薪与按标准工时的时薪，不随今日上限变化")
    func wageCaptionIgnoresLeave() throws {
        let state = try sending([.requestLeave(Leave(period: .afternoon, deductionPercent: 50))], to: try onboarded(), at: standardDay(9, 0))

        #expect(try attendancePanel(state, at: standardDay(11, 0)).caption == "满勤日薪 ¥1000 · 时薪 ¥142.8571")
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

    @Test("请下午假后进度条两端为当日计划：10:00 至 12:00")
    func progressTicksFollowLeave() throws {
        let state = try sending([.requestLeave(Leave(period: .afternoon, deductionPercent: 50))], to: try onboarded(), at: standardDay(9, 0))
        let progress = try #require(try attendancePanel(state, at: standardDay(11, 0)).progress)

        #expect([progress.startText, progress.endText] == ["上班 10:00", "下班 12:00"])
    }

    @Test("统计行的扣款叫「今日扣款」")
    func deductionStatTitle() throws {
        let stats = try attendancePanel(try onboarded(), at: standardDay(15, 0)).stats

        #expect(stats.map(\.title) == ["距离下班", "今日扣款", "本月累计"])
    }
}

@Suite("今日概览 760：休息日")
struct Panel760RestTests {
    @Test("周六：统计行为本月已上班 (已上班 / 应出勤) 与本月累计，标题下两行小字为说明与下一个上班日")
    func saturday() throws {
        let body = try panel(try onboarded(), at: moment(2026, 2, 14, 11, 0)).body

        #expect(body == .rest(RestPanel(
            headline: "今天休息",
            tagline: "不搬砖，不计钱。",
            nextAttendanceText: "下一个上班日 2月16日 周一",
            stats: [
                StatItem(title: "本月已上班", value: "10/20 天"),
                StatItem(title: "本月累计", value: "¥10000"),
            ]
        )))
    }

    @Test("全天请假：标题为今天请假，没有「不计钱」的说明 (请假可能扣薪)")
    func fullDayLeave() throws {
        let state = try sending([.requestLeave(Leave(period: .fullDay, deductionPercent: 100))], to: try onboarded(), at: standardDay(9, 0))
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
    @Test("按日薪 10%：扣 ¥100；日薪 20000 ÷ 21 时按完整精度折算后截掉末尾 0")
    func percentCharge() throws {
        let feb = try #require(try panel(try onboarded(), at: standardDay(15, 0)).deductionEntry)
        let may = try #require(try panel(try onboarded(), at: moment(2026, 5, 6, 15, 0)).deductionEntry)

        #expect(feb.chargeText(.percentOfDailyWage(10)) == "扣 ¥100")
        #expect(may.chargeText(.percentOfDailyWage(10)) == "扣 ¥95.2381")
        #expect(feb.chargeText(.fixed(50)) == "扣 ¥50")
    }
}

@Suite("请假表单 760")
struct Panel760LeaveTests {
    @Test("各时段的工时：全天 10:00–18:00，上午到午休开始，下午从午休结束")
    func periodHours() throws {
        let form = try #require(snapshot(of: try onboarded(), at: standardDay(9, 0)).leaveForm)

        #expect(form.periodHours == [.fullDay: "10:00–18:00", .morning: "10:00–12:00", .afternoon: "13:00–18:00"])
    }

    @Test("关闭午休时半天以计划上下班中点为界")
    func periodHoursWithoutLunch() throws {
        let schedule = WorkSchedule(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0), lunch: nil)
        let form = try #require(snapshot(of: try onboarded(schedule: schedule), at: standardDay(9, 0)).leaveForm)

        #expect(form.periodHours == [.fullDay: "10:00–18:00", .morning: "10:00–14:00", .afternoon: "14:00–18:00"])
    }

    @Test("请下午假 50%：汇总为今天改为 10:00–12:00 上班、请假扣薪 −¥500、今日上限 ¥500，输入框旁为 ¥500")
    func summaryWithAfternoonLeave() throws {
        let state = try sending([.requestLeave(Leave(period: .afternoon, deductionPercent: 50))], to: try onboarded(), at: standardDay(9, 0))
        let form = try #require(snapshot(of: state, at: standardDay(9, 0)).leaveForm)

        #expect(form.summary == [
            StatItem(title: "今天改为", value: "10:00–12:00 上班"),
            StatItem(title: "请假扣薪", value: "−¥500"),
            StatItem(title: "今日上限", value: "¥500"),
        ])
        #expect(form.deductionText == "¥500")
    }

    @Test("还没请假：今天改为作息原样，请假扣薪 ¥0")
    func summaryWithoutLeave() throws {
        let form = try #require(snapshot(of: try onboarded(), at: standardDay(9, 0)).leaveForm)

        #expect(form.summary == [
            StatItem(title: "今天改为", value: "10:00–18:00 上班"),
            StatItem(title: "请假扣薪", value: "¥0"),
            StatItem(title: "今日上限", value: "¥1000"),
        ])
        #expect(form.deductionText == "¥0")
    }

    @Test("全天请假：今天改为全天请假")
    func summaryWithFullDayLeave() throws {
        let state = try sending([.requestLeave(Leave(period: .fullDay, deductionPercent: 100))], to: try onboarded(), at: standardDay(9, 0))
        let form = try #require(snapshot(of: state, at: standardDay(11, 0)).leaveForm)

        #expect(form.summary.first == StatItem(title: "今天改为", value: "全天请假"))
    }
}
