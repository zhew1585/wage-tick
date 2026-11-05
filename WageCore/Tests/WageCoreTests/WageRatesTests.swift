import Foundation
import Testing
import WageCore

/// 「按这个作息算」(设计稿 P1 引导 · 2 作息 · 760)：本月上班日、满勤日薪、标准工时、时薪。
@Suite("工资换算")
struct WageRatesTests {
    private func rates(
        salary: Decimal = 20000, schedule: WorkSchedule = standardSchedule,
        at now: Moment = standardDay(9, 0), holidays: HolidayTable = .empty
    ) throws -> WageRates? {
        let state = try onboarded(salary: salary, schedule: schedule, at: now)
        return snapshot(of: state, at: now, holidays: holidays).wageRates
    }

    private func schedule(_ start: (Int, Int), _ end: (Int, Int), lunch: Bool = true) -> WorkSchedule {
        WorkSchedule(
            start: TimeOfDay(hour: start.0, minute: start.1),
            end: TimeOfDay(hour: end.0, minute: end.1),
            lunch: lunch ? .default : nil
        )
    }

    @Test("PRD 4.2.4 标准算例：20 个上班日，日薪 1000，标准工时 7 小时，时薪 142.8571")
    func standardExample() throws {
        let rates = try #require(try rates())

        #expect(rates.attendanceDays == StatItem(title: "本月上班日", value: "20 天"))
        #expect(rates.dailyWage == StatItem(title: "满勤日薪", value: "¥1000"))
        #expect(rates.standardHours == StatItem(title: "标准工时", value: "7 小时"))
        #expect(rates.hourlyWage == StatItem(title: "时薪", value: "¥142.8571"))
    }

    @Test("设计稿算例：2026 年 11 月 21 个上班日、默认作息，日薪 952.381，时薪 119.0476")
    func designExample() throws {
        let rates = try #require(try rates(schedule: .default, at: moment(2026, 11, 6, 10, 0)))

        #expect(rates.attendanceDays.value == "21 天")
        #expect(rates.dailyWage.value == "¥952.381")
        #expect(rates.standardHours.value == "8 小时")
        #expect(rates.hourlyWage.value == "¥119.0476")
    }

    @Test("PRD 4.2.3 #4 关闭午休：上下班之间全算标准工时")
    func lunchOff() throws {
        let rates = try #require(try rates(schedule: schedule((9, 0), (18, 0), lunch: false), at: moment(2026, 11, 6, 10, 0)))

        #expect(rates.standardHours.value == "9 小时")
        // 20000 ÷ 21 ÷ 9 = 105.82010…
        #expect(rates.hourlyWage.value == "¥105.8201")
    }

    @Test("标准工时不是整点：保留 1 位小数，与面板工作进度一致")
    func fractionalHours() throws {
        let rates = try #require(try rates(schedule: schedule((9, 0), (17, 30))))

        #expect(rates.standardHours.value == "7.5 小时")
        // 1000 ÷ 7.5 = 133.3333…
        #expect(rates.hourlyWage.value == "¥133.3333")
    }

    @Test("PRD 4.2.2 法定节假日不算上班日，日薪随之变大")
    func holidaysReduceAttendanceDays() throws {
        let holidays = HolidayTable(days: [LocalDate(year: 2026, month: 2, day: 16): .holiday])
        let rates = try #require(try rates(holidays: holidays))

        #expect(rates.attendanceDays.value == "19 天")
        // 20000 ÷ 19 = 1052.63157…
        #expect(rates.dailyWage.value == "¥1052.6316")
    }

    @Test("PRD 4.2.3 #2 改作息后按今天生效的作息算")
    func followsCurrentSchedule() throws {
        let state = try apply(
            .changeSchedule(schedule((9, 0), (18, 0), lunch: false)), to: try onboarded(), at: standardDay(9, 0)
        ).state

        #expect(snapshot(of: state, at: standardDay(9, 0)).wageRates?.standardHours.value == "9 小时")
    }

    @Test("未完成引导：没有工资换算")
    func notOnboarded() {
        #expect(snapshot(of: AppState(), at: standardDay(9, 0)).wageRates == nil)
    }
}
