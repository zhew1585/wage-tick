import Foundation
import Testing
import WageCore

// 首页改版去掉说明性前缀后要用的短文字：只有时刻或日期本身，与原有带前缀的字段出自同一处计算。
// 标准算例：2026 年 2 月 20 个应出勤日，日薪 1000，作息 10:00 至 18:00、饭点 12:00 至 13:00。

/// 把带前缀的旧文字去掉前缀，用来核对新旧字段一致。
private func dropping(_ prefix: String, from text: String?) -> String? {
    guard let text, text.hasPrefix(prefix) else { return nil }
    return String(text.dropFirst(prefix.count))
}

@Suite("首页改版：进度条两端只有时刻")
struct HomeProgressClockTests {
    @Test("正常上班日：10:00 与 18:00")
    func regularDay() throws {
        let progress = try #require(try attendancePanel(try onboarded(), at: standardDay(15, 0)).progress)

        #expect([progress.startClock, progress.endClock] == ["10:00", "18:00"])
        #expect(progress.startClock == dropping("上班 ", from: progress.startText))
        #expect(progress.endClock == dropping("下班 ", from: progress.endText))
    }

    @Test("请了后半天：下班时刻提前到 12:00")
    func afternoonOff() throws {
        let progress = try #require(try attendancePanel(try onLeave(secondHalfLeave(50)), at: standardDay(11, 0)).progress)

        #expect([progress.startClock, progress.endClock] == ["10:00", "12:00"])
        #expect(progress.endClock == dropping("下班 ", from: progress.endText))
    }

    @Test("请了前半天：上班时刻推后到 13:00")
    func morningOff() throws {
        let progress = try #require(try attendancePanel(try onLeave(firstHalfLeave(50)), at: standardDay(14, 0)).progress)

        #expect([progress.startClock, progress.endClock] == ["13:00", "18:00"])
        #expect(progress.startClock == dropping("上班 ", from: progress.startText))
    }
}

/// 从 `first` 起连续 `count` 天都标为放假的节假日表。
private func holidays(from first: (Int, Int, Int), days count: Int) -> HolidayTable {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = shanghai
    let start = calendar.date(from: DateComponents(year: first.0, month: first.1, day: first.2))!
    let dates = (0..<count).map { offset -> LocalDate in
        let parts = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: offset, to: start)!)
        return LocalDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }
    return HolidayTable(days: Dictionary(uniqueKeysWithValues: dates.map { ($0, HolidayKind.holiday) }))
}

/// 休息日面板；不是休息日时测试失败。
private func restPanel(_ state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> RestPanel {
    guard case .rest(let rest) = try #require(snapshot(of: state, at: now, holidays: holidays).panel).body else {
        Issue.record("期望休息日面板")
        throw PanelError.wrongBody
    }
    return rest
}

@Suite("首页改版：下一个上班日只有日期")
struct HomeNextAttendanceDateTests {
    @Test("今年内：周六看下周一，「2月16日 周一」")
    func sameYear() throws {
        let rest = try restPanel(try onboarded(), at: moment(2026, 2, 14, 11, 0))

        #expect(rest.nextAttendanceDate == "2月16日 周一")
        #expect(rest.nextAttendanceDate == dropping("下一个上班日 ", from: rest.nextAttendanceText))
    }

    @Test("跨年：12 月 28 日至 1 月 1 日放假，12 月 26 日周六看到「2027年1月4日 周一」")
    func nextYear() throws {
        let rest = try restPanel(try onboarded(), at: moment(2026, 12, 26, 11, 0), holidays: holidays(from: (2026, 12, 28), days: 5))

        #expect(rest.nextAttendanceDate == "2027年1月4日 周一")
        #expect(rest.nextAttendanceDate == dropping("下一个上班日 ", from: rest.nextAttendanceText))
    }

    @Test("一年内都没有应出勤日：与旧字段一样为 nil")
    func noneWithinYear() throws {
        let rest = try restPanel(try onboarded(), at: moment(2026, 2, 14, 11, 0), holidays: holidays(from: (2026, 2, 1), days: 450))

        #expect(rest.nextAttendanceDate == nil)
        #expect(rest.nextAttendanceText == nil)
    }
}

@Suite("首页改版：累计中目标的预计完成只有日期")
struct HomeActiveGoalFinishTests {
    @Test("今年内：A 10000 还需搬砖 9 天，「2月24日」")
    func sameYear() throws {
        let state = try creatingGoal("A", 10000, in: try onboarded(), at: standardDay(9, 0))
        let card = try activeGoal(state, at: standardDay(11, 0))

        #expect(card.finishText == "2月24日")
        #expect(card.estimate == "还需搬砖 9 天 · 2月24日")
    }

    @Test("不在今年：12 月 28 日下班后 A 3000 数 4 天到 2027 年 1 月 1 日，「2027年1月」")
    func nextYear() throws {
        let created = moment(2026, 12, 28, 18, 30)
        let state = try creatingGoal("A", 3000, in: try onboarded(at: created), at: created)

        #expect(try activeGoal(state, at: created).finishText == "2027年1月")
    }

    @Test("今天就能达成：「今天」")
    func reachableToday() throws {
        let state = try creatingGoal("A", 500, in: try onboarded(), at: standardDay(9, 0))
        let card = try activeGoal(state, at: standardDay(11, 0))

        #expect(card.finishText == "今天")
        #expect(card.estimate == "今天就能达成")
    }

    @Test("本月没有应出勤日 (日薪为 0)：没法预计，为 nil")
    func noEstimate() throws {
        let state = try creatingGoal("A", 10000, in: try onboarded(), at: standardDay(9, 0))
        let februaryOff = holidays(from: (2026, 2, 1), days: 28)
        let panel = try #require(snapshot(of: state, at: standardDay(11, 0), holidays: februaryOff).panel)
        guard case .active(let card) = panel.goal else {
            Issue.record("期望累计中目标")
            return
        }

        #expect(card.shortEstimate == "暂时没法预计")
        #expect(card.finishText == nil)
    }

    @Test("目标管理列表里的 asFirst 同样带 finishText")
    func goalListAsFirst() throws {
        var state = try creatingGoal("A", 10000, in: try onboarded(), at: standardDay(9, 0))
        state = try creatingGoal("B", 500, in: state, at: standardDay(9, 0))
        let queue = try #require(snapshot(of: state, at: standardDay(11, 0)).goals).queue

        #expect(queue.map(\.asFirst.finishText) == ["2月24日", "今天"])
    }

    @Test("已经攒够：排队中的 B 拖到第一个时累计额已超过目标额，预计完成是「今天」")
    func alreadyReached() throws {
        // 13:06 已累计 300，B 只要 200：排到第一个就达成。
        var state = try creatingGoal("A", 10000, in: try onboarded(), at: standardDay(9, 0))
        state = try creatingGoal("B", 200, in: state, at: standardDay(9, 0))
        let preview = try #require(snapshot(of: state, at: standardDay(13, 6)).goals?.queue.last?.asFirst)

        #expect(preview.estimate == "已经攒够，排到第一个就达成")
        #expect(preview.finishText == "今天")
    }
}

@Suite("首页改版：排队中目标的预计完成只有日期")
struct HomeQueuedGoalFinishTests {
    /// 依次新建若干目标后的状态。
    private func goals(_ goals: [(String, Decimal)], at now: Moment) throws -> AppState {
        try goals.reduce(try onboarded(at: now)) { try creatingGoal($1.0, $1.1, in: $0, at: now) }
    }

    @Test("今年内：B、C 依次「2月27日」「3月4日」")
    func sameYear() throws {
        let state = try goals([("A", 10000), ("B", 3000), ("C", 2500)], at: standardDay(9, 0))
        let queue = try #require(snapshot(of: state, at: standardDay(11, 0)).panel?.goalQueue)

        #expect(queue.upcoming.map(\.finishText) == ["2月27日", "3月4日"])
        #expect(queue.upcoming.map(\.shortEstimate) == ["预计 2月27日", "预计 3月4日"])
    }

    @Test("不在今年：B 到 2027 年 1 月 4 日，「2027年1月」")
    func nextYear() throws {
        let created = moment(2026, 12, 28, 18, 30)
        let state = try goals([("A", 1000), ("B", 2000)], at: created)
        let queue = try #require(snapshot(of: state, at: created).panel?.goalQueue)

        #expect(queue.upcoming.map(\.finishText) == ["2027年1月"])
        #expect(queue.upcoming.map(\.shortEstimate) == ["预计 2027年1月"])
    }

    @Test("本月没有应出勤日 (日薪为 0)：没法预计，为 nil")
    func noEstimate() throws {
        let state = try goals([("A", 10000), ("B", 3000)], at: standardDay(9, 0))
        let februaryOff = holidays(from: (2026, 2, 1), days: 28)
        let queue = try #require(snapshot(of: state, at: standardDay(11, 0), holidays: februaryOff).panel?.goalQueue)

        #expect(queue.upcoming.map(\.shortEstimate) == ["暂时没法预计"])
        #expect(queue.upcoming.map(\.finishText) == [nil])
    }
}

@Suite("首页改版：今天请假的扣薪比例")
struct HomeLeaveDeductionRateTests {
    /// 标准算例今天 09:00 的请假表单。
    private func form(_ state: AppState) throws -> LeaveForm {
        try #require(snapshot(of: state, at: standardDay(9, 0)).leaveForm)
    }

    @Test("部分请假 14:00 至 16:00 扣 28.57%：「扣薪 28.57%」，即整句「 · 」后面那段")
    func partial() throws {
        let form = try form(try onLeave(leave("14:00", "16:00", Decimal(string: "28.57")!)))

        #expect(form.deductionRateText == "扣薪 28.57%")
        #expect(form.currentText == "已请假 14:00–16:00 · 扣薪 28.57%")
    }

    @Test("全天请假扣 100%：「扣薪 100.00%」")
    func fullDay() throws {
        let form = try form(try onLeave(fullDayLeave(100)))

        #expect(form.deductionRateText == "扣薪 100.00%")
        #expect(form.currentText == "已请全天假 · 扣薪 100.00%")
    }

    @Test("扣 0%：与整句里的写法一致，「扣薪 0.00%」")
    func zero() throws {
        let form = try form(try onLeave(leave("14:00", "16:00", 0)))

        #expect(form.deductionRateText == "扣薪 0.00%")
        #expect(form.currentText == "已请假 14:00–16:00 · 扣薪 0.00%")
    }

    @Test("没请假：为 nil")
    func noLeave() throws {
        #expect(try form(try onboarded()).deductionRateText == nil)
    }
}
