import Foundation
import Testing
import WageCore

// 发薪日的展示 (issue #20)：概览页脚右侧的距发薪、发薪日表单下方说明本月实际发薪日。
// 算例同 PaydayTests：2026 年 11 月、双休；1 日周日，5 日周四，13 日周五，15 日周日，16 日周一，30 日周一。

private func at(_ day: Int, _ hour: Int = 15) -> Moment { moment(2026, 11, day, hour, 0) }

/// 2026-11-02 (周一) 双休完成引导；给了发薪日时再设好。
private func state(payday: Payday? = nil) throws -> AppState {
    let state = try onboarded(at: moment(2026, 11, 2, 9, 0))
    guard let payday else { return state }
    return try apply(.setPayday(payday), to: state, at: at(2)).state
}

private let fifteenthEarlier = Payday(dayOfMonth: 15, shift: .earlier)

private func footer(_ day: Int) throws -> PaydayFooter {
    try #require(snapshot(of: state(payday: fifteenthEarlier), at: at(day)).panel?.payday)
}

/// 11-05 打开发薪日表单时，按编辑中的发薪日给出的说明。
private func note(_ day: Int, _ shift: PaydayShift, holidays: HolidayTable = .empty) throws -> String {
    let form = try #require(snapshot(of: state(), at: at(5), holidays: holidays).settingsForm)
    return form.paydayNote(for: Payday(dayOfMonth: day, shift: shift))
}

private let rule = "填 29 到 31 时，小月按月末那天算。"

@Suite("发薪日的展示")
struct PaydayDisplayTests {
    @Test("页脚：11-05 距发薪 8 天，进度条 21 / 29")
    func footerCountdown() throws {
        let value = try footer(5)
        #expect(value.prefix == "距发薪")
        #expect(value.value == "8")
        #expect(value.suffix == "天")
        #expect(!value.isPayday)
        #expect(abs(value.progress - 21.0 / 29.0) < 1e-9)
    }

    @Test("页脚：前一天整句「明天发薪」，当天「今天发薪」满格")
    func footerAroundPayday() throws {
        let tomorrow = try footer(12)
        #expect(tomorrow.prefix == nil)
        #expect(tomorrow.value == "明天发薪")
        #expect(tomorrow.suffix == nil)
        #expect(!tomorrow.isPayday)
        let today = try footer(13)
        #expect(today.prefix == nil)
        #expect(today.value == "今天发薪")
        #expect(today.isPayday)
        #expect(today.progress == 1)
    }

    @Test("页脚：没设发薪日时没有距发薪")
    func footerNotSet() throws {
        #expect(snapshot(of: try state(), at: at(5)).panel?.payday == nil)
    }

    @Test("表单说明：15 号是周日，提前到 13 号、顺延到 16 号，或照常当天发")
    func noteShifts() throws {
        #expect(try note(15, .earlier) == rule + "这个月 15 号是周日，会提前到 13 号 (周五) 发。")
        #expect(try note(15, .later) == rule + "这个月 15 号是周日，会顺延到 16 号 (周一) 发。")
        #expect(try note(15, .unchanged) == rule + "这个月 15 号是周日，照常当天发。")
    }

    @Test("表单说明：那天要上班就当天发")
    func noteAttendanceDay() throws {
        #expect(try note(13, .earlier) == rule + "这个月 13 号是周五，当天发。")
    }

    @Test("表单说明：填 31 时 11 月按月末 30 号")
    func noteMonthEnd() throws {
        #expect(try note(31, .earlier) == rule + "这个月按月末 30 号 (周一) 算，当天发。")
    }

    @Test("表单说明：工作日放假时说不上班")
    func noteHoliday() throws {
        let holidays = HolidayTable(days: [LocalDate(year: 2026, month: 11, day: 13): .holiday])
        #expect(try note(13, .earlier, holidays: holidays) == rule + "这个月 13 号是周五，不上班，会提前到 12 号 (周四) 发。")
    }

    @Test("表单说明：提前跨到上个月时带上月份")
    func noteAcrossMonth() throws {
        #expect(try note(1, .earlier) == rule + "这个月 1 号是周日，会提前到 10 月 30 号 (周五) 发。")
    }

    @Test("表单说明：几号越界时只说规则，保存时由命令报错")
    func noteOutOfRange() throws {
        #expect(try note(0, .earlier) == rule)
        #expect(try note(32, .earlier) == rule)
    }
}
