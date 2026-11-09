import Foundation
import Testing
import WageCore

// 距离周末 (PRD V1.13，方案 B)：统计行里「今日扣款」换成「距离周末」，到下一个休息日 (不应出勤的日子) 还有几天，
// 按休息模式、法定节假日与调休判定；下一个休息日是法定节假日时叫「距离放假」。有扣款时扣款并到主数字下方的小字里。
// 算例落在 2026 年 11 月：2 日周一，5 日周四，6 日周五，7 日周六，8 日周日。

private func nov(_ day: Int) -> LocalDate { LocalDate(year: 2026, month: 11, day: day) }

private func at(_ day: Int, _ hour: Int = 11) -> Moment { moment(2026, 11, day, hour, 0) }

/// 2026-11-06 (周五) 按某个休息模式完成引导；大小周时 2 日那周为大周。
private func onboardedNov(_ choice: RestModeChoice) throws -> AppState {
    try onboarded(restMode: choice, at: at(6, 9))
}

private func panel(_ state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> TodayPanel {
    try #require(snapshot(of: state, at: now, holidays: holidays).panel)
}

private func stats(_ panel: TodayPanel) -> [StatItem] {
    switch panel.body {
    case .attendance(let body): body.stats
    case .rest(let body): body.stats
    case .unpaidWork(let body): body.stats
    }
}

/// 统计行里距离周末 (或距离放假) 那一项，「标题 值」。
private func weekend(_ state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> String? {
    try stats(panel(state, at: now, holidays: holidays)).first(where: \.isHighlighted).map { "\($0.title) \($0.value)" }
}

@Suite("距离周末")
struct WeekendCountdownTests {
    @Test("双休：周一 5 天，周五明天休息，周六正在休息")
    func twoDaysOff() throws {
        let state = try onboardedNov(.twoDaysOff)
        #expect(try weekend(state, at: at(2)) == "距离周末 5 天")
        #expect(try weekend(state, at: at(6)) == "距离周末 明天休息")
        #expect(try weekend(state, at: at(7)) == "距离周末 正在休息")
    }

    @Test("单休：只有周日休，周一 6 天，周六明天休息")
    func sundayOnly() throws {
        let state = try onboardedNov(.sundayOnly)
        #expect(try weekend(state, at: at(2)) == "距离周末 6 天")
        #expect(try weekend(state, at: at(7)) == "距离周末 明天休息")
        #expect(try weekend(state, at: at(8)) == "距离周末 正在休息")
    }

    @Test("大小周：大周周五明天休息，小周周一 6 天")
    func alternating() throws {
        let state = try onboardedNov(.bigWeekNow)
        #expect(try weekend(state, at: at(6)) == "距离周末 明天休息")
        #expect(try weekend(state, at: at(9)) == "距离周末 6 天")
        #expect(try weekend(state, at: at(14)) == "距离周末 明天休息")
    }

    @Test("下一个休息日是法定节假日时叫距离放假，放假当天正在休息")
    func holidayComesFirst() throws {
        let state = try onboardedNov(.twoDaysOff)
        let table = HolidayTable(days: [nov(4): .holiday])
        #expect(try weekend(state, at: at(2), holidays: table) == "距离放假 2 天")
        #expect(try weekend(state, at: at(3), holidays: table) == "距离放假 明天休息")
        #expect(try weekend(state, at: at(4), holidays: table) == "距离放假 正在休息")
    }

    @Test("调休上班的周六跳过，倒数到周日")
    func makeupDaySkipped() throws {
        let state = try onboardedNov(.twoDaysOff)
        let table = HolidayTable(days: [nov(7): .makeupDay])
        #expect(try weekend(state, at: at(6), holidays: table) == "距离周末 2 天")
    }

    @Test("全天请假仍是应出勤日，照常倒数")
    func fullDayLeaveStillCounts() throws {
        let fullDay = Leave(start: standardSchedule.start, end: standardSchedule.end, deductionPercent: 100)
        let state = try apply(.setLeave(fullDay), to: try onboardedNov(.twoDaysOff), at: at(5, 9)).state
        #expect(try weekend(state, at: at(5)) == "距离周末 2 天")
    }

    @Test("统计行：上班中为距离下班、距离周末、本月累计；已下班为今日结算、距离周末、本月累计；休息日距离周末排最后")
    func statsLayout() throws {
        let state = try onboardedNov(.twoDaysOff)
        #expect(stats(try panel(state, at: at(5, 15))).map(\.title) == ["距离下班", "距离周末", "本月累计"])
        #expect(stats(try panel(state, at: at(5, 19))).map(\.title) == ["今日结算", "距离周末", "本月累计"])
        #expect(stats(try panel(state, at: at(7))).map(\.title) == ["本月已上班", "本月累计", "距离周末"])
    }

    @Test("有扣款时扣款并到主数字下方的小字末尾，没有扣款时不出现")
    func deductionMovesToCaption() throws {
        let state = try onboardedNov(.twoDaysOff)
        let fined = try recordingDeduction(.fixed(50), on: state, at: at(5, 10))
        guard case .attendance(let working) = try panel(fined, at: at(5, 15)).body else {
            Issue.record("应为上班中")
            return
        }
        #expect(working.caption.hasSuffix(" · 扣款 −¥50"))
        guard case .attendance(let clean) = try panel(state, at: at(5, 15)).body else {
            Issue.record("应为上班中")
            return
        }
        #expect(!clean.caption.contains("扣款"))
        guard case .attendance(let offWork) = try panel(fined, at: at(5, 19)).body else {
            Issue.record("应为已下班")
            return
        }
        #expect(offWork.caption == "准点下班，赢 · 扣款 −¥50")
    }

    @Test("小组件中号右栏：上班的状态为距离下班、距离周末，其余为距离周末、本月累计")
    func widgetSideStats() throws {
        let state = try onboardedNov(.twoDaysOff)
        func side(_ now: Moment) -> [String] {
            guard case .today(let today) = widgetSnapshot(of: state, at: now) else { return [] }
            return today.sideStats.map(\.title)
        }
        #expect(side(at(5, 15)) == ["距离下班", "距离周末"])
        #expect(side(at(5, 19)) == ["距离周末", "本月累计"])
        #expect(side(at(7)) == ["距离周末", "本月累计"])
    }
}
