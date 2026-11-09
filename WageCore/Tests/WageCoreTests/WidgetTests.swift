import Foundation
import Testing
@testable import WageCore

// 桌面小组件 (PRD F14)：内容取自同一时刻的面板快照，时间线每分钟一条并在日状态切换处各有一条。
// 标准算例：2026-02-11 周三，日薪 1000，作息 10:00 至 18:00、饭点 12:00 至 13:00，标准工时 7 小时，时薪 142.8571。

private func widget(_ state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> WidgetToday {
    guard case .today(let today) = widgetSnapshot(of: state, at: now, holidays: holidays) else {
        Issue.record("期望已完成引导的小组件内容")
        throw CancellationError()
    }
    return today
}

private func amount(_ widget: WidgetToday) throws -> WidgetAmount {
    guard case .amount(let amount) = widget.main else {
        Issue.record("期望大数字主体")
        throw CancellationError()
    }
    return amount
}

private func applied(_ command: Command, to state: AppState, at now: Moment) throws -> AppState {
    try apply(command, to: state, at: now).state
}

@Suite("小组件内容")
struct WidgetSnapshotTests {
    @Test("上班中：主数字 2 位小数，倒计时到计划下班，中号右栏为距离下班与距离周末")
    func working() throws {
        let now = standardDay(15, 0)
        let widget = try widget(try onboarded(), at: now)
        let main = try amount(widget)
        let end = standardDay(18, 0).date

        #expect(widget.dateText == "2月11日 周三")
        #expect(widget.statusLabel == "上班中")
        #expect(widget.tone == .attendance)
        #expect(main.label == "今日已赚")
        #expect(main.amount == "571.43")
        #expect(main.caption == "满勤日薪 ¥1000 · 时薪 ¥142.86")
        #expect(main.footer == WidgetStat(title: "距离下班", value: .countdown(to: end)))
        let progress = try #require(main.progress)
        #expect(progress.percent == "57.14%")
        #expect(abs(progress.ratio - 4.0 / 7.0) < 1e-9)
        #expect(progress.segments.count == 2)
        #expect([progress.startTime, progress.endTime, progress.startText, progress.endText] == ["10:00", "18:00", "上班 10:00", "下班 18:00"])
        #expect(widget.stats.map(\.title) == ["距离下班", "距离周末", "本月累计"])
        #expect(widget.stats[0].value == .countdown(to: end))
        #expect(widget.stats[1] == WidgetStat(title: "距离周末", value: .text("3 天"), isHighlighted: true))
        #expect(widget.sideStats.map(\.title) == ["距离下班", "距离周末"])
    }

    @Test("未上班：主数字 0.00，距离下班同面板显示「-」")
    func notStarted() throws {
        let widget = try widget(try onboarded(), at: standardDay(9, 30))
        let main = try amount(widget)
        #expect(widget.statusLabel == "未上班")
        #expect(main.amount == "0.00")
        #expect(main.footer == WidgetStat(title: "距离下班", value: .text("-")))
    }

    @Test("干饭中：倒计时照样走到计划下班")
    func lunchBreak() throws {
        let widget = try widget(try onboarded(), at: standardDay(12, 30))
        #expect(widget.statusLabel == "干饭中")
        #expect(try amount(widget).footer.value == .countdown(to: standardDay(18, 0).date))
    }

    @Test("已下班：标签今日结算，整数也带 2 位小数，没有进度，底部一行是「准点下班，赢」，中号右栏不重复今日结算")
    func offWork() throws {
        let widget = try widget(try onboarded(), at: standardDay(18, 30))
        let main = try amount(widget)
        #expect(widget.statusLabel == "已下班")
        #expect(main.label == "今日结算")
        #expect(main.amount == "1000.00")
        #expect(main.progress == nil)
        #expect(main.footer == WidgetStat(title: "准点下班，赢", value: nil))
        #expect(widget.stats.map(\.title) == ["今日结算", "距离周末", "本月累计"])
        #expect(widget.sideStats.map(\.title) == ["距离周末", "本月累计"])
    }

    @Test("白干中：主数字为今日已倒贴，计时从 18:00 起正计时")
    func unpaidWork() throws {
        let state = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let widget = try widget(state, at: standardDay(19, 5, 12))
        let main = try amount(widget)
        let timer = WidgetValue.elapsed(since: standardDay(18, 0).date)
        #expect(widget.statusLabel == "白干中")
        #expect(widget.tone == .unpaidWork)
        #expect(main.label == "今日已倒贴")
        // 1:05:12 × 142.857142… = 155.2380…
        #expect(main.amount == "155.24")
        #expect(main.footer == WidgetStat(title: "18:00 起", value: timer))
        #expect(main.caption == "18:00 起 · 已白干")
        #expect(main.captionTimer == timer)
        #expect(widget.sideStats.map(\.title) == ["距离周末", "本月累计"])
    }

    @Test("白干第二段：计时从开始那天已白干的总时长接着走")
    func unpaidWorkSecondSegment() throws {
        var state = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        state = try applied(.stopUnpaidWork, to: state, at: standardDay(18, 30))
        state = try applied(.startUnpaidWork, to: state, at: standardDay(20, 0))
        let main = try amount(try widget(state, at: standardDay(20, 10)))
        // 已白干 30 + 10 分钟，计时起点在此刻往前 40 分钟。
        #expect(main.footer.value == .elapsed(since: standardDay(19, 30).date))
    }

    @Test("白干跨过零点：标签与起点带「昨天」，主数字是开始那天的，中号右栏是今天的距离周末与本月累计")
    func unpaidWorkPastMidnight() throws {
        let state = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let widget = try widget(state, at: moment(2026, 2, 12, 0, 30))
        let main = try amount(widget)
        #expect(widget.statusLabel == "白干中")
        #expect(main.label == "昨天已倒贴")
        #expect(main.amount == "928.57")
        #expect(main.footer == WidgetStat(title: "昨天 18:00 起", value: .elapsed(since: standardDay(18, 0).date)))
        #expect(widget.sideStats == [
            WidgetStat(title: "距离周末", value: .text("2 天"), isHighlighted: true),
            WidgetStat(title: "本月累计", value: .text("¥8000")),
        ])
    }

    @Test("休息日：小牛主体，下个上班日")
    func restDay() throws {
        let widget = try widget(try onboarded(), at: moment(2026, 2, 14, 10, 0))
        #expect(widget.statusLabel == "休息日")
        #expect(widget.tone == .rest)
        #expect(widget.main == .rest(WidgetRest(headline: "今天休息", nextAttendanceText: "下个上班日 2月16日 周一")))
        #expect(widget.sideStats.map(\.title) == ["距离周末", "本月累计"])
    }

    @Test("未完成引导：提示打开 App")
    func setup() {
        #expect(widgetSnapshot(of: AppState(), at: standardDay(15, 0)) == .setup(.standard))
    }

    @Test("目标：累计中卡片与最多 2 个排队中，同面板")
    func goals() throws {
        var state = try onboarded()
        for (name, amount) in [("Switch 2", 10000), ("去趟大理", 8000), ("跑路基金", 50000), ("换电脑", 12000)] {
            state = try applied(.createGoal(name: name, amount: Decimal(amount)), to: state, at: standardDay(9, 0))
        }
        let now = standardDay(15, 0)
        let widget = try widget(state, at: now)
        let panel = try #require(snapshot(of: state, at: now).panel)
        #expect(widget.goal == panel.goal)
        #expect(widget.queued.map(\.name) == ["去趟大理", "跑路基金"])
    }

    @Test("没有目标：空状态提示")
    func noGoal() throws {
        #expect(try widget(try onboarded(), at: standardDay(15, 0)).goal == .empty("给自己定个目标吧"))
    }
}

@Suite("小组件时间线")
struct WidgetTimelineTests {
    @Test("第一条在此刻，之后每个整分钟一条，排满 60 分钟")
    func everyMinute() throws {
        let now = standardDay(15, 0, 30)
        let dates = widgetTimeline(of: try onboarded(), from: now).map(\.date)
        #expect(dates.first == now.date)
        #expect(dates.count == 61)
        #expect(dates[1] == standardDay(15, 1).date)
        #expect(dates.last == standardDay(16, 0).date)
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("数字按每一条的时刻算，约每分钟更新一次")
    func amountsAdvance() throws {
        let entries = widgetTimeline(of: try onboarded(), from: standardDay(15, 0))
        guard case .today(let first) = entries[0].snapshot, case .today(let later) = entries[7].snapshot else {
            Issue.record("期望已完成引导")
            return
        }
        // 每分钟多赚 1000 ÷ 420 = 2.38。
        #expect(try amount(first).amount == "571.43")
        #expect(try amount(later).amount == "588.10")
    }

    @Test("计划下班那一刻正好有一条，切到已下班")
    func offWorkBoundary() throws {
        let entries = widgetTimeline(of: try onboarded(), from: standardDay(17, 30, 20))
        let boundary = try #require(entries.first { $0.date == standardDay(18, 0).date })
        guard case .today(let widget) = boundary.snapshot else { throw CancellationError() }
        #expect(widget.statusLabel == "已下班")
    }

    @Test("饭点开始那一刻切到干饭中，零点那一刻换成新的一天")
    func lunchAndMidnight() throws {
        let lunch = widgetTimeline(of: try onboarded(), from: standardDay(11, 59, 30))
        guard case .today(let eating) = try #require(lunch.first { $0.date == standardDay(12, 0).date }).snapshot else {
            throw CancellationError()
        }
        #expect(eating.statusLabel == "干饭中")

        let night = widgetTimeline(of: try onboarded(), from: standardDay(23, 30))
        guard case .today(let tomorrow) = try #require(night.first { $0.date == moment(2026, 2, 12, 0, 0).date }).snapshot else {
            throw CancellationError()
        }
        #expect(tomorrow.dateText == "2月12日 周四")
        #expect(tomorrow.statusLabel == "未上班")
    }

    @Test("请假在中间：请假开始与结束各有一条")
    func leaveBoundaries() throws {
        let leave = Leave(start: TimeOfDay(hour: 14, minute: 0), end: TimeOfDay(hour: 16, minute: 0), deductionPercent: 25)
        let state = try applied(.setLeave(leave), to: try onboarded(), at: standardDay(9, 0))
        let moments = widgetMoments(of: state, from: standardDay(13, 59, 50), holidays: .empty, horizon: 3 * 60 * 60)
        #expect(moments.contains(standardDay(14, 0).date))
        #expect(moments.contains(standardDay(16, 0).date))
    }

    @Test("每一条先推进到此刻：白干到计划上班自动停止，那一刻起不再是白干中")
    func autoStopAdvances() throws {
        let state = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let entries = widgetTimeline(of: state, from: moment(2026, 2, 12, 9, 30))
        guard case .today(let before) = entries[0].snapshot,
              case .today(let after) = try #require(entries.first { $0.date == moment(2026, 2, 12, 10, 0).date }).snapshot else {
            throw CancellationError()
        }
        #expect(before.statusLabel == "白干中")
        #expect(after.statusLabel == "上班中")
    }
}

@Suite("小组件格式与数据")
struct WidgetFormatTests {
    @Test("主数字：四舍五入到 2 位，永远 2 位小数", arguments: [("0", "0.00"), ("1000", "1000.00"), ("571.428571", "571.43"), ("22.3", "22.30")])
    func cents(value: String, expected: String) throws {
        #expect(Format.cents(try #require(Decimal(string: value))) == expected)
    }

    @Test("节假日表编码后原样读回 (单日覆盖与休息模式不存)")
    func holidayTableRoundTrip() throws {
        let table = HolidayTable(
            days: [LocalDate(year: 2026, month: 10, day: 1): .holiday, LocalDate(year: 2026, month: 9, day: 28): .makeupDay],
            missingYears: [2027]
        )
        let decoded = try JSONDecoder().decode(HolidayTable.self, from: JSONEncoder().encode(table))
        #expect(decoded == table)
    }
}
