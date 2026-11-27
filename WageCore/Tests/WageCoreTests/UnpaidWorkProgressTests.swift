import Foundation
import Testing
import WageCore

// 白干中进度区：从开始时刻走到自动停止时刻 (见 GLOSSARY「白干自动停止」) 的进度条。
// 作息 09:00 至 18:00、饭点 12:00 至 13:00，双休。2026-02-12 是周四，13 日周五，14、15 日周末，16 日周一。

private let nineToSix = WorkSchedule(
    start: TimeOfDay(hour: 9, minute: 0),
    end: TimeOfDay(hour: 18, minute: 0),
    lunch: LunchBreak(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 13, minute: 0))
)

private func feb(_ day: Int) -> LocalDate {
    LocalDate(year: 2026, month: 2, day: day)
}

private func applied(_ command: Command, to state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> AppState {
    try apply(command, to: state, at: now, holidays: holidays).state
}

/// 在 `start` 点了开始白干 (我还没走或被迫营业)，`now` 时白干中面板的进度区。
private func progress(
    _ state: AppState? = nil, startedAt start: Moment, now: Moment, holidays: HolidayTable = .empty
) throws -> WorkProgress {
    let base = try state ?? onboarded(schedule: nineToSix, at: moment(2026, 2, 1, 9, 0))
    let running = try applied(.startUnpaidWork, to: base, at: start, holidays: holidays)
    guard case .unpaidWork(let body) = try #require(snapshot(of: running, at: now, holidays: holidays).panel).body else {
        Issue.record("期望白干中面板")
        throw CancellationError()
    }
    return body.progress
}

/// 进度条只有一段，填到 `filled`。
private func expectSingleBar(_ progress: WorkProgress, filled: Double) {
    #expect(progress.segments.count == 1)
    #expect(progress.segments.first?.share == 1)
    #expect(abs((progress.segments.first?.filled ?? -1) - filled) < 1e-9)
}

@Suite("白干中进度区")
struct UnpaidWorkProgressTests {
    @Test("周四 18:00 开始、20:00 时：最多白干 15 小时、13.33%，左端 18:00，右端明天 09:00")
    func tomorrowMorning() throws {
        let progress = try progress(startedAt: moment(2026, 2, 12, 18, 0), now: moment(2026, 2, 12, 20, 0))

        #expect(progress.label == "最多白干 15 小时")
        #expect(progress.percent == "13.33%")
        #expect(progress.startDay == nil)
        #expect(progress.startClock == "18:00")
        #expect(progress.endDay == "明天")
        #expect(progress.endClock == "09:00")
        expectSingleBar(progress, filled: 2.0 / 15)
    }

    @Test("周五请了全天假、17:54 被迫营业，10 秒后：最多白干 63.1 小时、0.00%，右端周一 09:00")
    func fullDayLeaveFriday() throws {
        let leave = Leave(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 18, minute: 0), deductionPercent: 100)
        let onLeave = try applied(.setLeave(leave), to: try onboarded(schedule: nineToSix, at: moment(2026, 2, 1, 9, 0)), at: moment(2026, 2, 13, 8, 0))
        let progress = try progress(onLeave, startedAt: moment(2026, 2, 13, 17, 54), now: moment(2026, 2, 13, 17, 54, 10))

        #expect(progress.label == "最多白干 63.1 小时")
        #expect(progress.percent == "0.00%")
        #expect(progress.startDay == nil)
        #expect(progress.startClock == "17:54")
        #expect(progress.endDay == "周一")
        #expect(progress.endClock == "09:00")
    }

    @Test("周六 13:00 被迫营业、14:30 时：最多白干 44 小时、3.41%，右端周一 09:00")
    func saturday() throws {
        let progress = try progress(startedAt: moment(2026, 2, 14, 13, 0), now: moment(2026, 2, 14, 14, 30))

        #expect(progress.label == "最多白干 44 小时")
        #expect(progress.percent == "3.41%")
        #expect(progress.endDay == "周一")
        #expect(progress.endClock == "09:00")
        expectSingleBar(progress, filled: 1.5 / 44)
    }

    @Test("周四 18:00 开始、周五 06:45 时：左端昨天 18:00，右端只写 09:00 (停在今天)，85.00%")
    func pastMidnight() throws {
        let progress = try progress(startedAt: moment(2026, 2, 12, 18, 0), now: moment(2026, 2, 13, 6, 45))

        #expect(progress.label == "最多白干 15 小时")
        #expect(progress.percent == "85.00%")
        #expect(progress.startDay == "昨天")
        #expect(progress.startClock == "18:00")
        #expect(progress.endDay == nil)
        #expect(progress.endClock == "09:00")
        expectSingleBar(progress, filled: 0.85)
    }

    @Test("周四 23:30 (UTC+8) 开始，10 分钟后时区切到 UTC+9 (此刻周五 00:40)：左端按此刻的时区写 00:30，不带前缀")
    func timeZoneMovedEast() throws {
        let start = moment(2026, 2, 12, 23, 30)
        let now = Moment(date: start.date.addingTimeInterval(10 * 60), timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let progress = try progress(startedAt: start, now: now)

        #expect(progress.startDay == nil)
        #expect(progress.startClock == "00:30")
    }

    @Test("周六 07:30 (UTC+8) 被迫营业，40 分钟后时区切到 UTC+0 (此刻周六 00:10)：左端按此刻的时区写昨天 23:30")
    func timeZoneMovedWest() throws {
        let start = moment(2026, 2, 14, 7, 30)
        let now = Moment(date: start.date.addingTimeInterval(40 * 60), timeZone: TimeZone(identifier: "Europe/London")!)
        let progress = try progress(startedAt: start, now: now)

        #expect(progress.startDay == "昨天")
        #expect(progress.startClock == "23:30")
    }

    @Test("往后 60 天都不上班：右端是第 7 天的月日与 00:00")
    func fallbackMonthDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 2, day: 13))!
        let days = (0..<80).map { offset in
            let parts = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: offset, to: first)!)
            return (LocalDate(year: parts.year!, month: parts.month!, day: parts.day!), HolidayKind.holiday)
        }
        let longBreak = HolidayTable(days: Dictionary(uniqueKeysWithValues: days))
        let progress = try progress(startedAt: moment(2026, 2, 12, 18, 0), now: moment(2026, 2, 12, 20, 0), holidays: longBreak)

        // 周四 18:00 到 2月19日 00:00 共 150 小时。
        #expect(progress.label == "最多白干 150 小时")
        #expect(progress.percent == "1.33%")
        #expect(progress.endDay == "2月19日")
        #expect(progress.endClock == "00:00")
    }

    @Test("下一个应出勤日开头请了 09:00 至 11:00 的假：右端是请假后的上班时刻 明天 11:00")
    func leaveAtStartOfNextDay() throws {
        let leave = Leave(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 11, minute: 0), deductionPercent: 100)
        let base = try onboarded(schedule: nineToSix, at: moment(2026, 2, 1, 9, 0))
        let withLeave = try applied(.editDay(feb(13), .setLeave(leave)), to: base, at: moment(2026, 2, 12, 15, 0))
        let progress = try progress(withLeave, startedAt: moment(2026, 2, 12, 18, 0), now: moment(2026, 2, 12, 20, 0))

        #expect(progress.label == "最多白干 17 小时")
        #expect(progress.endDay == "明天")
        #expect(progress.endClock == "11:00")
    }

    @Test("上班中的进度区两端没有日子前缀")
    func attendanceHasNoDayPrefix() throws {
        let state = try onboarded(schedule: nineToSix, at: moment(2026, 2, 1, 9, 0))
        guard case .attendance(let body) = try #require(snapshot(of: state, at: moment(2026, 2, 12, 10, 0)).panel).body else {
            Issue.record("期望应出勤日面板")
            return
        }
        let progress = try #require(body.progress)
        #expect(progress.startDay == nil)
        #expect(progress.endDay == nil)
    }
}
