import Testing
@testable import WageCore

/// 改了上下班后自动带出的饭点：放在正中间，开始对齐到 10 分钟，两头各留至少 10 分钟。
struct LunchCenteringTests {
    private func time(_ text: String) -> TimeOfDay {
        let parts = text.split(separator: ":").map { Int($0)! }
        return TimeOfDay(hour: parts[0], minute: parts[1])
    }

    @Test("饭点居中", arguments: [
        ("09:00", "18:00", 60, "13:00", "14:00"),
        ("16:00", "23:00", 60, "19:00", "20:00"),
        ("10:00", "18:00", 60, "13:30", "14:30"),
        ("09:00", "17:50", 60, "13:00", "14:00"),
        ("16:00", "23:59", 30, "19:40", "20:10"),
        ("09:00", "10:20", 60, "09:10", "10:10"),
    ])
    func centered(start: String, end: String, length: Int, lunchStart: String, lunchEnd: String) throws {
        let lunch = try #require(LunchBreak.centered(between: time(start), and: time(end), length: length))
        #expect(lunch == LunchBreak(start: time(lunchStart), end: time(lunchEnd)))
        #expect(Validation.schedule(WorkSchedule(start: time(start), end: time(end), lunch: lunch)) == nil)
    }

    @Test("上下班之间放不下饭点 (两头各留 10 分钟) 时为 nil")
    func tooShort() {
        #expect(LunchBreak.centered(between: time("09:00"), and: time("10:10"), length: 60) == nil)
    }
}
