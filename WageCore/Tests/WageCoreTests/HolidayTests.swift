import Foundation
import Testing
import WageCore

// 法定节假日与调休 (PRD 4.2.2 判定顺序第 2 至 5 条，4.3.5 #10、#16)。
// 节假日表按 2026 年国务院放假安排 (holiday-cn 2026.json) 手工构造，只列测试用到的月份。

private func date(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)
}

/// 由放假日与调休上班日构造节假日表。
private func table(off: [LocalDate], work: [LocalDate], missingYears: Set<Int> = []) -> HolidayTable {
    let days = Dictionary(uniqueKeysWithValues: off.map { ($0, HolidayKind.holiday) } + work.map { ($0, HolidayKind.makeupDay) })
    return HolidayTable(days: days, missingYears: missingYears)
}

/// 2026 年春节 (2 月 15 日至 23 日放假，2 月 14 日、28 日周六上班)、中秋 (9 月 25 日至 27 日放假，9 月 20 日周日上班)、
/// 国庆 (10 月 1 日至 7 日放假，10 月 10 日周六上班)。
private let holidays2026 = table(
    off: (15...23).map { date(2026, 2, $0) } + (25...27).map { date(2026, 9, $0) } + (1...7).map { date(2026, 10, $0) },
    work: [date(2026, 2, 14), date(2026, 2, 28), date(2026, 9, 20), date(2026, 10, 10)]
)

@Suite("节假日：应出勤日数与日薪")
struct HolidayDailyWageTests {
    @Test("国庆：2026 年 10 月去掉 5 个放假的工作日、加上 10 月 10 日调休，应出勤 18 天，月薪 18000 日薪 1000")
    func nationalDay() throws {
        let state = try onboarded(salary: 18000)
        let today = try #require(snapshot(of: state, at: moment(2026, 10, 8, 15, 0), holidays: holidays2026).today)

        #expect(today.dailyWage == 1000)
    }

    @Test("春节：2026 年 2 月去掉 6 个放假的工作日、加上 2 个调休周六，应出勤 16 天，月薪 20000 日薪 1250")
    func springFestival() throws {
        let body = try attendancePanel(try onboarded(), at: moment(2026, 2, 24, 15, 0), holidays: holidays2026)

        #expect(body.caption.hasPrefix("满勤日薪 ¥1250 ·"))
    }

    @Test("中秋：2026 年 9 月放假的 9 月 25 日周五与调休的 9 月 20 日周日相抵，仍是 22 天")
    func midAutumn() throws {
        let state = try onboarded(salary: 22000)
        let today = try #require(snapshot(of: state, at: moment(2026, 9, 21, 15, 0), holidays: holidays2026).today)

        #expect(today.dailyWage == 1000)
    }
}

@Suite("节假日：日状态")
struct HolidayDayStatusTests {
    @Test("调休上班的周六 2026-10-10 为应出勤：15:00 上班中，菜单栏显示今日已赚")
    func makeupSaturdayIsAttendanceDay() throws {
        let snap = snapshot(of: try onboarded(salary: 18000), at: moment(2026, 10, 10, 15, 0), holidays: holidays2026)

        #expect(snap.today?.status == .working)
        #expect(snap.panel?.statusLabel == "上班中")
        #expect(snap.menuBar.text == "571.4286")
    }

    @Test("调休上班的周日 2026-09-20 为应出勤")
    func makeupSundayIsAttendanceDay() throws {
        let snap = snapshot(of: try onboarded(), at: moment(2026, 9, 20, 9, 0), holidays: holidays2026)

        #expect(snap.today?.status == .notStarted)
    }

    @Test("法定节假日 2026-10-05 周一为休息日：今天休息，本月已上班 0 天，下一个应出勤日跳过国庆到 10月8日 周四")
    func holidayIsRestDay() throws {
        let snap = snapshot(of: try onboarded(salary: 18000), at: moment(2026, 10, 5, 15, 0), holidays: holidays2026)

        #expect(snap.today?.status == .restDay)
        #expect(snap.menuBar == MenuBarDisplay(pose: .sunbathing, text: nil))
        #expect(snap.panel?.body == .rest(RestPanel(
            headline: "今天休息",
            tagline: "不搬砖，不计钱。",
            nextAttendanceText: "下一个上班日 10月8日 周四",
            stats: [
                StatItem(title: "本月已上班", value: "0/18 天"),
                StatItem(title: "本月累计", value: "¥0"),
            ]
        )))
    }

    @Test("调休上班日的下一个应出勤日：2026-02-13 周五之后是调休上班的 2 月 14 日周六")
    func nextAttendanceDayCanBeMakeupDay() throws {
        let snap = snapshot(of: try onboarded(), at: moment(2026, 2, 13, 15, 0), holidays: holidays2026)

        #expect(snap.today?.nextAttendanceDay == date(2026, 2, 14))
    }
}

@Suite("节假日：数据更新与缺失")
struct HolidayDataTests {
    @Test("4.3.5 #16 节假日数据更新导致日薪变化：同一状态换上新数据后当月结算全部重算")
    func dataUpdateRecalculatesMonth() throws {
        // 2026-10-09 周五 18:30 已下班。
        let state = try onboarded(salary: 18000)
        let at = moment(2026, 10, 9, 18, 30)

        // 只按双休：10 月 22 个应出勤日，今天之前已过 1、2、5、6、7、8 日共 6 天。
        let before = try attendancePanel(state, at: at)
        #expect(before.stats == [
            StatItem(title: "今日结算", value: "¥818.1818"),
            StatItem(title: "今日扣款", value: "¥0"),
            StatItem(title: "本月累计", value: "¥5727.2727"),
        ])

        // 拿到节假日数据后：18 个应出勤日，日薪 1000，今天之前只有 10 月 8 日。
        let after = try attendancePanel(state, at: at, holidays: holidays2026)
        #expect(after.headline == "¥1000.0000")
        #expect(after.stats == [
            StatItem(title: "今日结算", value: "¥1000"),
            StatItem(title: "今日扣款", value: "¥0"),
            StatItem(title: "本月累计", value: "¥2000"),
        ])
    }

    @Test("AC-HOME-08 新一年数据获取失败：顶部提示【2027年的节假日数据没拿到，调休日请在日历里手动标记】，按双休继续计算")
    func missingYearShowsNoticeAndFallsBackToWeekends() throws {
        let missing2027 = HolidayTable(days: [:], missingYears: [2027])
        // 2027-01-01 周五：真实安排是元旦放假，缺数据时按双休当作应出勤日。
        let snap = snapshot(of: try onboarded(), at: moment(2027, 1, 1, 15, 0), holidays: missing2027)

        #expect(snap.panel?.notices == ["2027年的节假日数据没拿到，调休日请在日历里手动标记"])
        #expect(snap.today?.status == .working)
        // 2027 年 1 月只按双休有 21 个应出勤日。
        #expect(snap.today?.dailyWage == Decimal(20000) / 21)
    }

    @Test("AC-HOME-08 休息日同样显示缺失提示")
    func missingYearNoticeOnRestDay() throws {
        let snap = snapshot(of: try onboarded(), at: moment(2027, 1, 2, 15, 0), holidays: HolidayTable(days: [:], missingYears: [2027]))

        #expect(snap.panel?.notices == ["2027年的节假日数据没拿到，调休日请在日历里手动标记"])
    }

    @Test("只有今天所在年份缺失才提示：今年有数据时，别的年份缺失不打扰")
    func otherYearMissingShowsNoNotice() throws {
        let snap = snapshot(of: try onboarded(), at: moment(2026, 10, 8, 15, 0), holidays: HolidayTable(days: holidays2026.days, missingYears: [2027]))

        #expect(snap.panel?.notices == [])
    }

    @Test("不传节假日表时等同空表：只按双休，不提示缺失")
    func defaultTableIsWeekendsOnly() throws {
        let state = try onboarded(salary: 18000)
        let at = moment(2026, 10, 5, 15, 0)

        #expect(snapshot(of: state, at: at) == snapshot(of: state, at: at, holidays: .empty))
        #expect(snapshot(of: state, at: at).today?.status == .working)
        #expect(snapshot(of: state, at: at).panel?.notices == [])
    }
}

/// 带节假日表取应出勤日面板；不是应出勤日面板时测试失败。
private func attendancePanel(_ state: AppState, at now: Moment, holidays: HolidayTable) throws -> AttendancePanel {
    let panel = try #require(snapshot(of: state, at: now, holidays: holidays).panel)
    guard case .attendance(let body) = panel.body else {
        Issue.record("期望应出勤日面板，实际为 \(panel.body)")
        throw PanelError.wrongBody
    }
    return body
}

@Suite("节假日：命令里的应出勤判定")
struct HolidayCommandTests {
    private let fifty = DeductionInput(amount: .fixed(50), reason: nil, note: "")

    @Test("PRD 4.3.5 #8 国庆放假当天不能记扣钱，调休上班的周六可以")
    func deductionFollowsHolidayTable() throws {
        let state = try onboarded()

        #expect(throws: CommandError.notAttendanceDay) {
            try apply(.addDeduction(fifty), to: state, at: moment(2026, 10, 5, 11, 0), holidays: holidays2026)
        }
        #expect(throws: Never.self) {
            try apply(.addDeduction(fifty), to: state, at: moment(2026, 10, 10, 11, 0), holidays: holidays2026)
        }
    }

    @Test("PRD 4.3.5 #8 国庆放假当天不能请假，调休上班的周六可以")
    func leaveFollowsHolidayTable() throws {
        let state = try onboarded()
        let leave = Command.requestLeave(Leave(period: .fullDay, deductionPercent: 100))

        #expect(throws: CommandError.notAttendanceDay) {
            try apply(leave, to: state, at: moment(2026, 10, 5, 11, 0), holidays: holidays2026)
        }
        let makeupDay = moment(2026, 10, 10, 11, 0)
        let onLeave = try apply(leave, to: state, at: makeupDay, holidays: holidays2026).state
        #expect(snapshot(of: onLeave, at: makeupDay, holidays: holidays2026).today?.leave?.period == .fullDay)
        #expect(snapshot(of: state, at: moment(2026, 10, 5, 11, 0), holidays: holidays2026).leaveForm == nil)
    }
}
