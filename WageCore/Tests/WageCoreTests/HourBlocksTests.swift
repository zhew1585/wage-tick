import Testing
@testable import WageCore

private func applied(_ command: Command, to state: AppState, at now: Moment) throws -> AppState {
    try apply(command, to: state, at: now).state
}

@Suite("大胆版首页：进度格与头图小牛")
struct HourBlocksTests {
    @Test("上班中 15:00：7 格填 4 格，写已工作 4 / 7 小时、57.14%")
    func working() throws {
        let panel = try #require(snapshot(of: try onboarded(), at: standardDay(15, 0)).panel)
        let blocks = try #require(panel.blocks)

        #expect(blocks.count == 7)
        #expect(abs(blocks.filled - 4) < 0.01)
        #expect(!blocks.overtime)
        #expect(blocks.label == "已工作 4 / 7 小时")
        #expect(blocks.value == "57.14%")
        #expect(panel.cowScene == .working)
        #expect(panel.cowBubble.prefix == "距下班")
        #expect(panel.cowBubble.value == "3:00")
    }

    @Test("已下班：7 格全满")
    func offWork() throws {
        let panel = try #require(snapshot(of: try onboarded(), at: standardDay(18, 30)).panel)
        let blocks = try #require(panel.blocks)

        #expect(blocks.filled == 7)
        #expect(blocks.value == "100.00%")
        #expect(panel.cowScene == .offWork)
    }

    @Test("下班后白干 1:05：工时格全满，多一格超时，右上 +1:05")
    func unpaidAfterWork() throws {
        let state = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let blocks = try #require(snapshot(of: state, at: standardDay(19, 5, 12)).panel?.blocks)

        #expect(blocks.count == 7)
        #expect(blocks.filled == 7)
        #expect(blocks.overtime)
        #expect(blocks.value == "+1:05")
        #expect(blocks.isUnpaid)
    }

    @Test("休息日被迫营业 1:30：按一个标准工作日 7 格填 1.5 格；超过一整天全满、格数不变")
    func unpaidOnRestDay() throws {
        let saturday = { (hour: Int, minute: Int) in moment(2026, 2, 14, hour, minute) }
        let state = try applied(.startUnpaidWork, to: try onboarded(), at: saturday(10, 0))
        let short = try #require(snapshot(of: state, at: saturday(11, 30)).panel?.blocks)
        let long = try #require(snapshot(of: state, at: saturday(20, 0)).panel?.blocks, "超过一整天")

        #expect(short.count == 7)
        #expect(abs(short.filled - 1.5) < 0.01)
        #expect(!short.overtime)
        #expect(short.label == "已白干 1:30 / 7 小时")
        #expect(long.count == 7)
        #expect(long.filled == 7)
        #expect(long.value == "+10:00")
    }

    @Test("休息日没在白干：没有进度格")
    func restDay() throws {
        let saturday = moment(2026, 2, 14, 10, 0)
        let panel = try #require(snapshot(of: try onboarded(), at: saturday).panel)

        #expect(panel.blocks == nil)
        #expect(panel.cowScene == .restDay)
    }
}
