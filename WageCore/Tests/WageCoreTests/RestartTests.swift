import Foundation
import Testing
import WageCore

@Suite("重启与睡眠恢复")
struct RestartTests {
    @Test("PRD 4.3.5 #14 重启后配置仍在：状态存成 JSON 再读回，快照不变")
    func stateSurvivesPersistence() throws {
        let state = try onboarded(salary: Decimal(string: "12345.67")!)
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(snapshot(of: restored, at: standardDay(15, 0)) == snapshot(of: state, at: standardDay(15, 0)))
    }

    @Test("PRD 4.3.5 #14 睡眠或退出一段时间后，用更晚的此刻取快照，收入没有缺口")
    func laterMomentHasNoGap() throws {
        let state = try onboarded(at: standardDay(9, 0))

        // 09:00 之后再也没有任何命令，直接在 15:00 和次日 11:00 取快照。
        #expect(snapshot(of: state, at: standardDay(15, 0)).menuBar.text == "571.4286")
        #expect(snapshot(of: state, at: moment(2026, 2, 12, 11, 0)).menuBar.text == "142.8571")
    }

    @Test("PRD 4.3.5 #11 切换时区：按新时区的当前时间重新推导")
    func followsCurrentTimeZone() throws {
        let state = try onboarded()
        // 上海 15:00 等于东京 16:00。
        let tokyo = Moment(date: standardDay(15, 0).date, timeZone: TimeZone(identifier: "Asia/Tokyo")!)

        #expect(snapshot(of: state, at: tokyo).menuBar.text == "714.2857")
    }
}

@Suite("读回状态时拒绝不合法内容")
struct CorruptStateTests {
    private static let validProfile = """
    {"installDate":{"year":2026,"month":2,"day":11},"launchAtLogin":true,
     "salaries":[{"month":{"year":2026,"month":2},"amount":"20000"}],
     "schedule":{"start":{"hour":10,"minute":0},"end":{"hour":18,"minute":0},
                 "lunch":{"start":{"hour":12,"minute":0},"end":{"hour":13,"minute":0}}}}
    """

    private func decode(_ profile: String) throws -> AppState {
        try JSONDecoder().decode(AppState.self, from: Data("{\"profile\":\(profile)}".utf8))
    }

    @Test("合法内容可以读回")
    func validStateDecodes() throws {
        let state = try decode(Self.validProfile)

        #expect(snapshot(of: state, at: standardDay(11, 0)).menuBar.text == "142.8571")
    }

    @Test(
        "PRD 4.3.5 #1 至 #4 文件里的配置不合法时拒绝读入，不让快照崩溃",
        arguments: [
            ("\"salaries\":[{\"month\":{\"year\":2026,\"month\":2},\"amount\":\"20000\"}]", "\"salaries\":[]"),
            ("\"amount\":\"20000\"", "\"amount\":\"0\""),
            ("\"end\":{\"hour\":18,\"minute\":0},\n", "\"end\":{\"hour\":9,\"minute\":0},\n"),
            ("\"start\":{\"hour\":10,\"minute\":0}", "\"start\":{\"hour\":25,\"minute\":0}"),
            ("\"start\":{\"hour\":12,\"minute\":0}", "\"start\":{\"hour\":8,\"minute\":0}"),
        ]
    )
    func invalidStateIsRejected(replacement: (String, String)) {
        let corrupted = Self.validProfile.replacingOccurrences(of: replacement.0, with: replacement.1)
        #expect(corrupted != Self.validProfile)

        #expect(throws: DecodingError.self) { try decode(corrupted) }
    }
}
