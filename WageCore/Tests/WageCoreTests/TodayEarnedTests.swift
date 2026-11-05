import Foundation
import Testing
import WageCore

/// PRD 4.3.4 标准算例表中与今日已赚相关的一行。
struct StandardRow: Sendable, CustomTestStringConvertible {
    let hour: Int
    let minute: Int
    let status: DayStatus
    let pose: CowPose
    let progress: String  // 工作进度，四舍五入到 4 位
    let menuBarText: String

    var testDescription: String { String(format: "%02d:%02d", hour, minute) }
}

@Suite("今日已赚：标准算例")
struct TodayEarnedTests {
    @Test(
        "PRD 4.3.4 标准算例 (无扣钱各行，18:00 行按无扣钱取 1000) / AC-BAR-01 至 04：今日已赚、日状态与小牛",
        arguments: [
            StandardRow(hour: 9, minute: 30, status: .notStarted, pose: .yawning, progress: "0", menuBarText: "0.0000"),
            StandardRow(hour: 11, minute: 0, status: .working, pose: .grinding, progress: "0.1429", menuBarText: "142.8571"),
            StandardRow(hour: 12, minute: 30, status: .lunchBreak, pose: .sleeping, progress: "0.2857", menuBarText: "285.7143"),
            StandardRow(hour: 15, minute: 0, status: .working, pose: .grinding, progress: "0.5714", menuBarText: "571.4286"),
            StandardRow(hour: 18, minute: 0, status: .offWork, pose: .lyingFlat, progress: "1", menuBarText: "1000.0000"),
            StandardRow(hour: 18, minute: 30, status: .offWork, pose: .lyingFlat, progress: "1", menuBarText: "1000.0000"),
        ]
    )
    func standardExample(row: StandardRow) throws {
        let state = try onboarded()
        let snap = snapshot(of: state, at: standardDay(row.hour, row.minute))

        let today = try #require(snap.today)
        let earnings = try #require(today.earnings)
        #expect(today.status == row.status)
        #expect(earnings.cap == 1000)
        #expect(rounded4(earnings.progress) == Decimal(string: row.progress)!)
        #expect(snap.menuBar == MenuBarDisplay(pose: row.pose, text: row.menuBarText))
    }
}

@Suite("今日已赚：日薪与滚动")
struct DailyWageTests {
    @Test("PRD 4.2.4 标准算例：月薪 20000、应出勤 20 天，日薪 1000，每秒约 0.0397")
    func standardDailyWage() throws {
        let snap = snapshot(of: try onboarded(), at: standardDay(11, 0))

        let today = try #require(snap.today)
        #expect(today.dailyWage == 1000)
        #expect(rounded4(try #require(today.earnings).perSecond) == Decimal(string: "0.0397")!)
    }

    @Test("PRD 4.2.4 日薪精度：月薪 20000、应出勤 22 天，日薪保留完整精度")
    func dailyWageKeepsFullPrecision() throws {
        // 2026 年 3 月只按双休有 22 个应出勤日；未来月份沿用最近一次设置的月薪 (PRD 4.2.1 #3)。
        let snap = snapshot(of: try onboarded(), at: moment(2026, 3, 2, 18, 30))

        let today = try #require(snap.today)
        #expect(today.dailyWage == Decimal(20000) / Decimal(22))
        #expect(snap.menuBar.text == "909.0909")
    }

    @Test("AC-BAR-05 休息日：周六只显示晒太阳的小牛，无数字")
    func saturdayIsRestDay() throws {
        let snap = snapshot(of: try onboarded(), at: moment(2026, 2, 14, 11, 0))

        #expect(snap.today?.status == .restDay)
        #expect(snap.today?.earnings == nil)
        #expect(snap.menuBar == MenuBarDisplay(pose: .sunbathing, text: nil))
    }

    @Test("AC-BAR-02 上班中滚动：11:00 起每一刻都比上一刻多")
    func earnedKeepsGrowingWhileWorking() throws {
        let state = try onboarded()
        let start = standardDay(11, 0).date
        let earned = try [0, 0.1, 1, 10].map { offset in
            let now = Moment(date: start.addingTimeInterval(offset), timeZone: shanghai)
            return try #require(snapshot(of: state, at: now).today?.earnings).earned
        }

        #expect(earned == earned.sorted())
        #expect(Set(earned).count == earned.count)
        #expect(rounded4(earned[3]) == Decimal(string: "143.2540")!)
    }

    @Test("AC-BAR-03 午休暂停：12:30 观察 10 秒，停在 285.7143")
    func earnedPausesDuringLunch() throws {
        let state = try onboarded()

        #expect(snapshot(of: state, at: standardDay(12, 30)).menuBar.text == "285.7143")
        #expect(snapshot(of: state, at: standardDay(12, 30, 10)).menuBar.text == "285.7143")
    }

    @Test("PRD 4.3.3 状态边界：到达计划上班、午休开始、午休结束、计划下班即切换")
    func statusSwitchesExactlyAtBoundaries() throws {
        let state = try onboarded()
        let statuses = [(10, 0), (12, 0), (13, 0), (18, 0)].map { hour, minute in
            snapshot(of: state, at: standardDay(hour, minute)).today?.status
        }

        #expect(statuses == [.working, .lunchBreak, .working, .offWork])
    }

    @Test("PRD 4.2.3 #4 关闭午休：计划上下班之间全部计入有效工时")
    func noLunchCountsWholeDay() throws {
        let schedule = WorkSchedule(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0), lunch: nil)
        let snap = snapshot(of: try onboarded(schedule: schedule), at: standardDay(12, 30))

        // 10:00 至 12:30 共 2.5 小时，占 8 小时的 31.25%。
        #expect(snap.today?.status == .working)
        #expect(snap.today?.earnings?.progress == Decimal(string: "0.3125")!)
        #expect(snap.menuBar == MenuBarDisplay(pose: .grinding, text: "312.5000"))
    }

    @Test("AC-BAR-06 无文字：任意状态下菜单栏只有数字和小数点，没有 ¥")
    func menuBarTextIsDigitsOnly() throws {
        let state = try onboarded()
        let moments = [standardDay(9, 30), standardDay(11, 0), standardDay(12, 30), standardDay(18, 30), moment(2026, 2, 14, 11, 0)]
        let digitsOnly = /^[0-9]+\.[0-9]{4}$/

        for now in moments {
            if let text = snapshot(of: state, at: now).menuBar.text {
                #expect(text.wholeMatch(of: digitsOnly) != nil, "菜单栏出现了多余字符：\(text)")
            }
        }
    }
}

@Suite("今日已赚：是否在增长")
struct IsEarningTests {
    @Test("PRD 4.3.3 不变量 3 今日已赚只在上班中增长", arguments: [
        (9, 30, false), (11, 0, true), (12, 30, false), (18, 30, false),
    ])
    func onlyGrowsWhileWorking(hour: Int, minute: Int, expected: Bool) throws {
        let snap = snapshot(of: try onboarded(), at: standardDay(hour, minute))

        #expect(snap.today?.isEarning == expected)
    }
}

@Suite("今日已赚：展示取舍")
struct RollingFormatTests {
    @Test("PRD 4.7.1 #5 滚动区域四舍五入到 4 位：恰好 0.00005 进位为 0.0001")
    func roundsHalfUp() throws {
        // 月薪 28.8 ÷ 20 天 = 日薪 1.44；10:00 至 18:00 不午休共 28800 秒，第 1 秒正好赚 0.00005。
        let schedule = WorkSchedule(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0), lunch: nil)
        let state = try onboarded(salary: Decimal(string: "28.8")!, schedule: schedule)

        #expect(snapshot(of: state, at: standardDay(10, 0, 1)).menuBar.text == "0.0001")
    }
}
