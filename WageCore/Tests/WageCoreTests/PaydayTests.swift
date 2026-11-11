import Foundation
import Testing
import WageCore

// 发薪日与距发薪 (issue #20)：每月几号发，碰上不应出勤的日子按设置提前、顺延或不变。
// 距发薪 = 今天到下一个实际发薪日的自然日天数；发薪周期进度 = 上一个实际发薪日到下一个之间已过的比例。
// 算例落在 2026 年 11 月、双休：5 日周四，13 日周五，15 日周日，16 日周一，30 日周一；10-15 周四，12-15 周二。

private func date(_ month: Int, _ day: Int) -> LocalDate { LocalDate(year: 2026, month: month, day: day) }

private func at(_ month: Int, _ day: Int) -> Moment { moment(2026, month, day, 11, 0) }

/// 2026-11-02 (周一) 双休完成引导，再设好发薪日。
private func withPayday(_ day: Int, _ shift: PaydayShift) throws -> AppState {
    let state = try onboarded(at: moment(2026, 11, 2, 9, 0))
    return try apply(.setPayday(Payday(dayOfMonth: day, shift: shift)), to: state, at: at(11, 2)).state
}

private func countdown(
    _ state: AppState, at now: Moment, holidays: HolidayTable = .empty
) throws -> PaydayCountdown {
    try #require(snapshot(of: state, at: now, holidays: holidays).today?.paydayCountdown)
}

@Suite("发薪日")
struct PaydayTests {
    @Test("15 号遇周日：提前到 13 号周五 8 天，顺延到 16 号周一 11 天，不变 10 天")
    func shiftModes() throws {
        let earlier = try countdown(withPayday(15, .earlier), at: at(11, 5))
        #expect(earlier.days == 8)
        #expect(earlier.next == date(11, 13))
        let later = try countdown(withPayday(15, .later), at: at(11, 5))
        #expect(later.days == 11)
        #expect(later.next == date(11, 16))
        let unchanged = try countdown(withPayday(15, .unchanged), at: at(11, 5))
        #expect(unchanged.days == 10)
        #expect(unchanged.next == date(11, 15))
    }

    @Test("提前：12 日明天发薪，13 日当天，14 日起倒数到 12-15 (31 天)")
    func aroundPayday() throws {
        let state = try withPayday(15, .earlier)
        #expect(try countdown(state, at: at(11, 12)).days == 1)
        let today = try countdown(state, at: at(11, 13))
        #expect(today.days == 0)
        #expect(today.progress == 1)
        let after = try countdown(state, at: at(11, 14))
        #expect(after.days == 31)
        #expect(after.next == date(12, 15))
        #expect(after.previous == date(11, 13))
    }

    @Test("周期进度：10-15 发过，下一个 11-13，11-05 已过 21 / 29")
    func cycleProgress() throws {
        let value = try countdown(withPayday(15, .earlier), at: at(11, 5))
        #expect(value.previous == date(10, 15))
        #expect(value.progress == Decimal(21) / Decimal(29))
    }

    @Test("填 31 时小月按月末：11 月是 30 号 (周一)")
    func monthEnd() throws {
        let value = try countdown(withPayday(31, .earlier), at: at(11, 5))
        #expect(value.next == date(11, 30))
        #expect(value.days == 25)
    }

    @Test("落在法定节假日同样调整：13 号放假时提前到 12 号")
    func statutoryHoliday() throws {
        let holidays = HolidayTable(days: [date(11, 13): .holiday])
        let value = try countdown(withPayday(13, .earlier), at: at(11, 5), holidays: holidays)
        #expect(value.next == date(11, 12))
    }

    @Test("提前可以跨月：11-01 周日提前到 10-30 周五")
    func earlierAcrossMonth() throws {
        let state = try withPayday(1, .earlier)
        let value = try countdown(state, at: at(10, 29))
        #expect(value.next == date(10, 30))
        #expect(value.days == 1)
        // 10-30 发过后，下一个是 12-01 (周二)。
        #expect(try countdown(state, at: at(10, 31)).next == date(12, 1))
    }

    @Test("没设发薪日：没有距发薪，设置里显示未设置")
    func notSet() throws {
        let state = try onboarded(at: moment(2026, 11, 2, 9, 0))
        let snap = snapshot(of: state, at: at(11, 5))
        #expect(snap.today?.paydayCountdown == nil)
        #expect(snap.settingsForm?.payday == nil)
        #expect(snap.settingsForm?.paydayText == "未设置")
    }

    @Test("设置页文案：每月 15 号 · 遇休息日提前 / 顺延；不变时只写几号")
    func settingsText() throws {
        let text = { (shift: PaydayShift) in
            snapshot(of: try withPayday(15, shift), at: at(11, 5)).settingsForm?.paydayText
        }
        #expect(try text(.earlier) == "每月 15 号 · 遇休息日提前")
        #expect(try text(.later) == "每月 15 号 · 遇休息日顺延")
        #expect(try text(.unchanged) == "每月 15 号")
        #expect(snapshot(of: try withPayday(15, .later), at: at(11, 5)).settingsForm?.payday
            == Payday(dayOfMonth: 15, shift: .later))
    }

    @Test("几号只能 1 到 31；引导前不能设")
    func validation() throws {
        let state = try onboarded(at: moment(2026, 11, 2, 9, 0))
        for day in [0, 32] {
            #expect(throws: CommandError.paydayOutOfRange) {
                try apply(.setPayday(Payday(dayOfMonth: day, shift: .earlier)), to: state, at: at(11, 2))
            }
        }
        #expect(throws: CommandError.notOnboarded) {
            try apply(.setPayday(Payday(dayOfMonth: 15, shift: .earlier)), to: AppState(), at: at(11, 2))
        }
    }

    @Test("存盘往返保留发薪日；旧文件没有发薪日时读为未设置")
    func persistence() throws {
        let state = try withPayday(15, .later)
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)

        let old = try onboarded(at: moment(2026, 11, 2, 9, 0))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(old))
        #expect(snapshot(of: restored, at: at(11, 5)).settingsForm?.payday == nil)
    }

    @Test("存盘里几号越界时拒绝读入")
    func corruptFile() throws {
        let state = try withPayday(15, .earlier)
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
            .replacingOccurrences(of: "\"dayOfMonth\":15", with: "\"dayOfMonth\":40")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AppState.self, from: Data(json.utf8))
        }
    }
}
