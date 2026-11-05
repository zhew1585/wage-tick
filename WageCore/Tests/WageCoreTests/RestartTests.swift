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
