import Foundation
import Testing
import WageCore

// 按天算工资 (issue #16，PRD V1.16)：日薪直接用填的数；只有应出勤日有钱，周末与法定节假日都是 0；
// 本月累计 = 日薪 × 本月实际上班天数，请假照常扣；和月薪一样按月记录，修改对本月整月生效。
// 算例：2026-02-11 (周三)，10:00 至 18:00、饭点 12:00 至 13:00 (标准工时 7 小时)，日薪 200。

private func onboardedDaily(_ amount: Decimal = 200, at now: Moment = moment(2026, 2, 11, 9, 0)) throws -> AppState {
    let input = OnboardingInput(salary: amount, payBasis: .daily, schedule: standardSchedule)
    return try apply(.completeOnboarding(input), to: AppState(), at: now).state
}

private func attendance(_ state: AppState, at now: Moment) throws -> AttendancePanel {
    guard case .attendance(let body) = try #require(snapshot(of: state, at: now).panel).body else {
        throw MissingAttendance()
    }
    return body
}

private struct MissingAttendance: Error {}

/// 2026 年国庆：10 月 1 日至 7 日放假，10 日 (周六) 调休上班。
private let nationalDay = HolidayTable(days: Dictionary(uniqueKeysWithValues:
    (1...7).map { (LocalDate(year: 2026, month: 10, day: $0), HolidayKind.holiday) }
        + [(LocalDate(year: 2026, month: 10, day: 10), HolidayKind.makeupDay)]
))

@Suite("按天算工资")
struct DailyPayTests {
    @Test("日薪直接用填的数，与当月应出勤天数无关；今日已赚按工作进度")
    func dailyWageIsTheInput() throws {
        let snap = snapshot(of: try onboardedDaily(), at: standardDay(15, 0))
        #expect(snap.today?.dailyWage == 200)
        #expect(snap.menuBar.text == "114.2857")
    }

    @Test("本月累计 = 日薪 × 已上班天数 + 今日已赚；小字为「日薪 · 时薪」，没有「满勤」")
    func monthToDateAndCaption() throws {
        let body = try attendance(try onboardedDaily(), at: standardDay(15, 0))
        // 2 月 11 日之前 7 个应出勤日 × 200 + 114.29。
        #expect(body.stats.last == StatItem(title: "本月累计", value: "¥1514.29"))
        #expect(body.caption == "日薪 ¥200 · 时薪 ¥28.57")
    }

    @Test("法定节假日与周末没有工资：国庆整周 0 元，节后照常")
    func holidaysEarnNothing() throws {
        let state = try onboardedDaily(at: moment(2026, 10, 1, 9, 0))
        let holiday = snapshot(of: state, at: moment(2026, 10, 5, 15, 0), holidays: nationalDay)
        #expect(holiday.today?.status == .restDay)
        #expect(holiday.today?.monthToDate == 0)
        // 10 月 8 日 (节后第一个上班日) 下班后：之前 0 天 + 今天 200。
        let after = snapshot(of: state, at: moment(2026, 10, 8, 18, 30), holidays: nationalDay)
        #expect(after.today?.monthToDate == 200)
    }

    @Test("引导第 2 步的换算：日薪一项叫「日薪」")
    func wageRatesTitle() throws {
        let rates = try #require(snapshot(of: try onboardedDaily(), at: standardDay(9, 0)).wageRates)
        #expect(rates.dailyWage == StatItem(title: "日薪", value: "¥200"))
    }

    @Test("设置：本月工资显示「日薪 ¥200」，表单预先选中日薪")
    func settingsForm() throws {
        let form = try #require(snapshot(of: try onboardedDaily(), at: standardDay(15, 0)).settingsForm)
        #expect(form.payBasis == .daily)
        #expect(form.salaryText == "200")
        #expect(form.salaryDisplay == "日薪 ¥200")
    }

    @Test("月薪改成日薪：对本月整月生效，本月已过去的日子也按日薪算")
    func switchToDailyMidMonth() throws {
        let changed = try apply(.changeSalary(300, basis: .daily), to: try onboarded(), at: standardDay(10, 0)).state
        let snap = snapshot(of: changed, at: standardDay(18, 30))
        #expect(snap.today?.dailyWage == 300)
        #expect(snap.today.map { rounded4($0.monthToDate) } == 2400)
        #expect(snap.settingsForm?.salaryDisplay == "日薪 ¥300")
    }

    @Test("日薪不能是 0：提示「日薪得是个正数」")
    func dailyWageMustBePositive() throws {
        #expect(throws: CommandError.dailyWageNotPositive) {
            try apply(.changeSalary(0, basis: .daily), to: try onboarded(), at: standardDay(10, 0))
        }
        #expect(CommandError.dailyWageNotPositive.message == "日薪得是个正数")
        #expect(Validation.salary(0, basis: .monthly) == .salaryNotPositive)
    }

    @Test("历史月日历：工资条为「本月日薪 · 应出勤 20 天」与「¥200 · 满勤 ¥4000」(满勤 = 应出勤天数 × 日薪)")
    func historySalaryRow() throws {
        let month = try #require(snapshot(of: try onboardedDaily(), at: standardDay(15, 0)).historyMonth(YearMonth(year: 2026, month: 2)))
        #expect(month.salaryCaption == "本月日薪 · 应出勤 20 天")
        #expect(month.salaryText == "¥200 · 满勤 ¥4000")
        #expect(month.payBasis == .daily)
    }

    @Test("单日详情「这天上不上班」的说明按月 / 按天不同")
    func overrideNote() throws {
        let date = LocalDate(year: 2026, month: 2, day: 10)
        let daily = try #require(snapshot(of: try onboardedDaily(), at: standardDay(15, 0)).historyDay(date))
        #expect(daily.detail.editing.overrideNote == "按天算：改成不上班，这一天就没有工资，其他日子不受影响。")
        let monthly = try #require(snapshot(of: try onboarded(), at: standardDay(15, 0)).historyDay(date))
        #expect(monthly.detail.editing.overrideNote == "改了会影响本月应出勤天数，整月日薪跟着重算。")
    }

    @Test("历史里改往月为日薪只影响那个月，下个月保留原来的方式")
    func pastMonthKeepsNextMonth() throws {
        let state = try onboarded(at: moment(2026, 1, 15, 9, 0))
        let edited = try apply(
            .setSalary(YearMonth(year: 2026, month: 1), 250, basis: .daily), to: state, at: standardDay(10, 0)
        ).state
        let jan = try #require(snapshot(of: edited, at: standardDay(10, 0)).historyMonth(YearMonth(year: 2026, month: 1)))
        #expect(jan.payBasis == .daily)
        #expect(jan.salaryCaption == "1月日薪 · 应出勤 22 天")
        let feb = snapshot(of: edited, at: standardDay(10, 0))
        #expect(feb.settingsForm?.payBasis == .monthly)
        #expect(feb.today?.dailyWage == 1000)
    }

    @Test("旧数据的工资记录没有方式字段，读回为按月")
    func legacyDefaultsToMonthly() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(try onboarded())) as? [String: Any])
        var profile = try #require(json["profile"] as? [String: Any])
        var salaries = try #require(profile["salaries"] as? [[String: Any]])
        salaries = salaries.map { var entry = $0; entry["basis"] = nil; return entry }
        profile["salaries"] = salaries
        json["profile"] = profile
        let restored = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(snapshot(of: restored, at: standardDay(15, 0)).settingsForm?.payBasis == .monthly)
    }

    @Test("按天算的状态存盘后读回仍是按天")
    func persists() throws {
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(try onboardedDaily()))
        #expect(snapshot(of: restored, at: standardDay(15, 0)).today?.dailyWage == 200)
    }
}
