import Foundation
import Testing
import WageCore

// 休息模式 (PRD 4.2.2，V1.9)：双休、单休、大小周。一周从周一算起。
// 算例落在 2026 年 11 月：1 日周日，2 日周一，30 天里 4 个周六 (7、14、21、28)、5 个周日。
// 只按休息模式时 11 月应出勤：双休 21 天，单休 25 天，大小周 (2 日那周为大周) 23 天。

private func date(_ year: Int, _ month: Int, _ day: Int) -> LocalDate {
    LocalDate(year: year, month: month, day: day)
}

private func nov(_ day: Int) -> LocalDate { date(2026, 11, day) }

/// 2026-11-06 (周五) 的某个时刻，本组算例里的"今天"。
private func friday(_ hour: Int, _ minute: Int = 0) -> Moment { moment(2026, 11, 6, hour, minute) }

private func applied(_ command: Command, to state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> AppState {
    try apply(command, to: state, at: now, holidays: holidays).state
}

/// 在 2026-11-06 按某个休息模式完成引导。
private func onboardedNov(_ choice: RestModeChoice, at now: Moment = friday(9)) throws -> AppState {
    try onboarded(restMode: choice, at: now)
}

/// 某天的判定来源文案，取 `now` 时的快照 (历史只覆盖安装当月至本月)。
private func sourceLabel(_ state: AppState, _ day: LocalDate, at now: Moment = friday(15), holidays: HolidayTable = .empty) throws -> String {
    try #require(snapshot(of: state, at: now, holidays: holidays).historyDay(day)).detail.source.label
}

/// 某月日历上写的「应出勤 N 天」。
private func attendanceCaption(_ state: AppState, _ month: YearMonth, at now: Moment = friday(15)) throws -> String {
    try #require(snapshot(of: state, at: now).historyMonth(month)).salaryCaption
}

private let november = YearMonth(year: 2026, month: 11)

@Suite("休息模式：应出勤日")
struct RestModeAttendanceTests {
    @Test(
        "2026 年 11 月应出勤日数与日薪：双休 21 天 ¥952.38，单休 25 天 ¥800，大小周 23 天 ¥869.57",
        arguments: [
            (RestModeChoice.twoDaysOff, "21 天", "¥952.38"),
            (.sundayOnly, "25 天", "¥800"),
            (.bigWeekNow, "23 天", "¥869.57"),
            (.smallWeekNow, "23 天", "¥869.57"),
        ]
    )
    func novemberCounts(choice: RestModeChoice, days: String, wage: String) throws {
        let rates = try #require(snapshot(of: try onboardedNov(choice), at: friday(10)).wageRates)

        #expect(rates.attendanceDays.value == days)
        #expect(rates.dailyWage.value == wage)
    }

    @Test("双休：周六日都休，判定来源「双休」")
    func twoDaysOff() throws {
        let state = try onboardedNov(.twoDaysOff)

        #expect(try sourceLabel(state, nov(6)) == "工作日")
        #expect(try sourceLabel(state, nov(7)) == "双休")
        #expect(try sourceLabel(state, nov(8)) == "双休")
    }

    @Test("单休：周六上班 (判定来源「工作日」)，周日休 (判定来源「单休」)")
    func sundayOnly() throws {
        let state = try onboardedNov(.sundayOnly)

        #expect(try sourceLabel(state, nov(7)) == "工作日")
        #expect(try sourceLabel(state, nov(8)) == "单休")
        #expect(try #require(snapshot(of: state, at: friday(15)).historyDay(nov(7))).kind != .rest)
        #expect(try #require(snapshot(of: state, at: friday(15)).historyDay(nov(8))).kind == .rest)
    }

    @Test("大小周，这周 (11 月 2 日那周) 选休两天：7、8 日大周，14 日上班、15 日小周，21、22 日大周，28 日上班、29 日小周")
    func bigWeekNow() throws {
        let state = try onboardedNov(.bigWeekNow)

        #expect(try [7, 8, 14, 15, 21, 22, 28, 29].map { try sourceLabel(state, nov($0)) }
            == ["大周", "大周", "工作日", "小周", "大周", "大周", "工作日", "小周"])
        #expect(try attendanceCaption(state, november) == "本月月薪 · 应出勤 23 天")
    }

    @Test("大小周，这周选休一天：大小与选休两天正好相反")
    func smallWeekNow() throws {
        let state = try onboardedNov(.smallWeekNow)

        #expect(try [7, 8, 14, 15, 21, 22, 28, 29].map { try sourceLabel(state, nov($0)) }
            == ["工作日", "小周", "大周", "大周", "工作日", "小周", "大周", "大周"])
    }

    @Test("大小周跨月跨年一周一换：11 月 30 日那周为大周 (12 月 5 日休)，12 月 12 日上班，2027 年 1 月 2 日休、9 日上班")
    func parityAcrossMonthAndYear() throws {
        let state = try onboardedNov(.bigWeekNow)
        let later = moment(2027, 1, 15, 15, 0)

        #expect(try sourceLabel(state, date(2026, 12, 5), at: later) == "大周")
        #expect(try sourceLabel(state, date(2026, 12, 6), at: later) == "大周")
        #expect(try sourceLabel(state, date(2026, 12, 12), at: later) == "工作日")
        #expect(try sourceLabel(state, date(2026, 12, 13), at: later) == "小周")
        #expect(try sourceLabel(state, date(2027, 1, 2), at: later) == "大周")
        #expect(try sourceLabel(state, date(2027, 1, 9), at: later) == "工作日")
        // 12 月：31 天，周日 4 个，周六 5、19 日休，12、26 日上班。
        #expect(try attendanceCaption(state, YearMonth(year: 2026, month: 12), at: later) == "12月月薪 · 应出勤 25 天")
    }

    @Test("大小周往前推：11 月 20 日 (16 日那周) 选休两天，同月 7 日 (前两周) 也是大周，14 日 (前一周) 是小周")
    func parityBeforeAnchor() throws {
        let now = moment(2026, 11, 20, 9, 0)
        let state = try onboardedNov(.bigWeekNow, at: now)

        #expect(try sourceLabel(state, nov(7), at: now) == "大周")
        #expect(try sourceLabel(state, nov(14), at: now) == "工作日")
        #expect(try sourceLabel(state, nov(15), at: now) == "小周")
        #expect(try sourceLabel(state, nov(21), at: now) == "大周")
    }
}

@Suite("休息模式：节假日、调休与单日覆盖优先")
struct RestModePrecedenceTests {
    /// 假想的 11 月节假日表：8 日周日调休上班，14 日周六放假，21 日周六放假。
    private let table = HolidayTable(days: [
        nov(8): .makeupDay,
        nov(14): .holiday,
        nov(21): .holiday,
    ])

    @Test(
        "调休上班 > 法定节假日 > 休息模式，各模式一致",
        arguments: [RestModeChoice.twoDaysOff, .bigWeekNow, .smallWeekNow, .sundayOnly]
    )
    func holidayTableWins(choice: RestModeChoice) throws {
        let state = try onboardedNov(choice)

        #expect(try sourceLabel(state, nov(8), holidays: table) == "调休上班")
        #expect(try sourceLabel(state, nov(14), holidays: table) == "法定节假日")
        #expect(try sourceLabel(state, nov(21), holidays: table) == "法定节假日")
    }

    @Test("单休：周六放假日不上班、周日调休上班，应出勤 25 - 2 + 1 = 24 天")
    func sundayOnlyCount() throws {
        let rates = try #require(snapshot(of: try onboardedNov(.sundayOnly), at: friday(10), holidays: table).wageRates)

        #expect(rates.attendanceDays.value == "24 天")
    }

    @Test("大小周 (2 日那周大周)：14 日小周周六本应上班，放假后不上班；21 日大周本来就休；8 日调休上班，共 23 - 1 + 1 = 23 天")
    func alternatingCount() throws {
        let rates = try #require(snapshot(of: try onboardedNov(.bigWeekNow), at: friday(10), holidays: table).wageRates)

        #expect(rates.attendanceDays.value == "23 天")
    }

    @Test("单日覆盖最优先：大周周六改成上班、小周周六改成不上班，判定来源单日覆盖")
    func overrideWins() throws {
        var state = try onboardedNov(.bigWeekNow)
        state = try applied(.editDay(nov(7), .setOverride(.attendanceDay)), to: state, at: friday(15))
        state = try applied(.editDay(nov(14), .setOverride(.dayOff)), to: state, at: friday(15))

        #expect(try sourceLabel(state, nov(7)) == "单日覆盖")
        #expect(try sourceLabel(state, nov(14)) == "单日覆盖")
        #expect(try #require(snapshot(of: state, at: friday(10)).wageRates).attendanceDays.value == "23 天")
    }
}

@Suite("休息模式：修改")
struct RestModeChangeTests {
    @Test("11 月 6 日从双休改成单休：本月整月按 25 天重算，已过去的日子跟着按 ¥800 结算")
    func appliesToWholeCurrentMonth() throws {
        let state = try onboarded(restMode: .twoDaysOff, at: moment(2026, 10, 15, 9, 0))
        let before = try #require(snapshot(of: state, at: friday(19)).today)
        #expect(rounded4(before.dailyWage) == Decimal(string: "952.381")!)

        let changed = try applied(.changeRestMode(.sundayOnly), to: state, at: friday(15))
        let today = try #require(snapshot(of: changed, at: friday(19)).today)

        #expect(today.dailyWage == 800)
        // 11 月 2 日至 6 日 5 个应出勤日，都按新日薪结算。
        #expect(today.monthToDate == 4000)
        #expect(try attendanceCaption(changed, november) == "本月月薪 · 应出勤 25 天")
    }

    @Test("过去的月份保留当时的模式：10 月仍按双休 22 天，12 月沿用单休 27 天")
    func earlierMonthsKeepTheirMode() throws {
        let state = try onboarded(restMode: .twoDaysOff, at: moment(2026, 10, 15, 9, 0))
        let changed = try applied(.changeRestMode(.sundayOnly), to: state, at: friday(15))
        let december = moment(2026, 12, 10, 15, 0)

        #expect(try attendanceCaption(changed, YearMonth(year: 2026, month: 10), at: december) == "10月月薪 · 应出勤 22 天")
        #expect(try sourceLabel(changed, date(2026, 10, 31), at: december) == "双休")
        #expect(try attendanceCaption(changed, YearMonth(year: 2026, month: 12), at: december) == "本月月薪 · 应出勤 27 天")
    }

    @Test("同一个月改两次：以最后一次为准")
    func lastChangeWins() throws {
        var state = try onboardedNov(.twoDaysOff)
        state = try applied(.changeRestMode(.sundayOnly), to: state, at: friday(15))
        state = try applied(.changeRestMode(.smallWeekNow), to: state, at: friday(16))

        #expect(try sourceLabel(state, nov(7)) == "工作日")
        #expect(try sourceLabel(state, nov(14)) == "大周")
    }

    @Test("未完成引导时不能改休息模式")
    func requiresOnboarding() {
        #expect(throws: CommandError.notOnboarded) {
            try apply(.changeRestMode(.sundayOnly), to: AppState(), at: friday(15))
        }
    }
}

@Suite("休息模式：引导与设置")
struct RestModeFormTests {
    @Test("引导不选时默认双休")
    func onboardingDefaultsToTwoDaysOff() throws {
        let input = OnboardingInput(monthlySalary: 20000, schedule: standardSchedule)
        let state = try applied(.completeOnboarding(input), to: AppState(), at: friday(9))

        #expect(input.restMode == .twoDaysOff)
        #expect(snapshot(of: state, at: friday(9)).settingsForm?.restModeText == "双休")
    }

    @Test(
        "设置页的值与预选：双休、单休、大小周 · 这周休两天 / 一天",
        arguments: [
            (RestModeChoice.twoDaysOff, "双休"),
            (.sundayOnly, "单休"),
            (.bigWeekNow, "大小周 · 这周休两天"),
            (.smallWeekNow, "大小周 · 这周休一天"),
        ]
    )
    func settingsValue(choice: RestModeChoice, text: String) throws {
        let form = try #require(snapshot(of: try onboardedNov(choice), at: friday(15)).settingsForm)

        #expect(form.restModeChoice == choice)
        #expect(form.restModeText == text)
    }

    @Test("大小周每周一翻转：周日还是这周休两天，下周一变成这周休一天，再下周一又变回来")
    func flipsWeekly() throws {
        let state = try onboardedNov(.bigWeekNow)
        let text = { (now: Moment) in snapshot(of: state, at: now).settingsForm?.restModeText }

        #expect(text(moment(2026, 11, 8, 23, 59)) == "大小周 · 这周休两天")
        #expect(text(moment(2026, 11, 9, 0, 0)) == "大小周 · 这周休一天")
        #expect(text(moment(2026, 11, 16, 9, 0)) == "大小周 · 这周休两天")
        #expect(snapshot(of: state, at: moment(2026, 11, 9, 9, 0)).settingsForm?.restModeChoice == .smallWeekNow)
    }

    @Test("四个选项的标题与小字按设计稿顺序")
    func choiceLabels() {
        #expect(RestModeChoice.allCases.map(\.title) == ["双休", "大小周", "大小周", "单休"])
        #expect(RestModeChoice.allCases.map(\.subtitle) == ["周六日都休", "这周休两天", "这周休一天", "只休周日"])
    }
}

@Suite("休息模式：白干自动停止")
struct RestModeUnpaidWorkTests {
    @Test("单休：周五开始不停，停在周六 10:00；周六开始不停，跳过周日停在周一 10:00")
    func sundayOnlyAutoStop() throws {
        let state = try onboardedNov(.sundayOnly)
        let fromFriday = try applied(.startUnpaidWork, to: state, at: friday(18))
        #expect(snapshot(of: fromFriday, at: moment(2026, 11, 7, 9, 59)).today?.unpaidWork.isRunning == true)
        let stoppedSaturday = try applied(.advance, to: fromFriday, at: moment(2026, 11, 7, 10, 0))
        #expect(snapshot(of: stoppedSaturday, at: moment(2026, 11, 7, 10, 0)).today?.unpaidWork.isRunning == false)

        let fromSaturday = try applied(.startUnpaidWork, to: stoppedSaturday, at: moment(2026, 11, 7, 18, 0))
        #expect(snapshot(of: fromSaturday, at: moment(2026, 11, 9, 9, 59)).today?.unpaidWork.isRunning == true)
        let stoppedMonday = try applied(.advance, to: fromSaturday, at: moment(2026, 11, 9, 10, 0))
        #expect(snapshot(of: stoppedMonday, at: moment(2026, 11, 9, 10, 0)).today?.unpaidWork.isRunning == false)
    }

    @Test("双休：周五开始不停，周六 10:00 还在计时")
    func twoDaysOffKeepsRunningOnSaturday() throws {
        let running = try applied(.startUnpaidWork, to: try onboardedNov(.twoDaysOff), at: friday(18))

        #expect(snapshot(of: running, at: moment(2026, 11, 7, 10, 30)).today?.unpaidWork.isRunning == true)
    }
}

@Suite("休息模式：存储")
struct RestModePersistenceTests {
    @Test("存成 JSON 再读回：大小周的大小不变")
    func roundTrip() throws {
        let state = try onboardedNov(.smallWeekNow)
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(snapshot(of: restored, at: friday(15)).settingsForm?.restModeText == "大小周 · 这周休一天")
    }

    @Test("V1.9 之前的文件没有休息模式：读回为双休，11 月 21 天")
    func legacyDefaultsToTwoDaysOff() throws {
        let state = try onboardedNov(.sundayOnly)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var profile = try #require(json["profile"] as? [String: Any])
        #expect(profile["restModes"] != nil)
        profile["restModes"] = nil
        json["profile"] = profile
        let restored = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        let snap = snapshot(of: restored, at: friday(15))

        #expect(snap.settingsForm?.restModeChoice == .twoDaysOff)
        #expect(snap.wageRates?.attendanceDays.value == "21 天")
    }

    @Test("读回时大周锚点不是周一、休息模式为空：当作损坏文件", arguments: [
        #"[{"month":{"year":2026,"month":11},"mode":{"kind":"alternating","bigWeekMonday":{"year":2026,"month":11,"day":3}}}]"#,
        "[]",
    ])
    func rejectsInvalid(restModes: String) throws {
        let state = try onboardedNov(.bigWeekNow)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var profile = try #require(json["profile"] as? [String: Any])
        profile["restModes"] = try JSONSerialization.jsonObject(with: Data(restModes.utf8))
        json["profile"] = profile
        let data = try JSONSerialization.data(withJSONObject: json)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AppState.self, from: data) }
    }
}
