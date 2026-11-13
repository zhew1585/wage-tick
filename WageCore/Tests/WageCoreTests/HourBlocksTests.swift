import Testing
@testable import WageCore

private func applied(_ command: Command, to state: AppState, at now: Moment) throws -> AppState {
    try apply(command, to: state, at: now).state
}

@Suite("大胆版首页：进度格与头图小牛")
struct HourBlocksTests {
    @Test("上班中 15:00：7 格填 4 格，写已搬砖 4 / 7 小时、57%，下面上班、饭点、下班")
    func working() throws {
        let panel = try #require(snapshot(of: try onboarded(), at: standardDay(15, 0)).panel)
        let blocks = try #require(panel.blocks)

        #expect(blocks.count == 7)
        #expect(abs(blocks.filled - 4) < 0.01)
        #expect(!blocks.overtime)
        #expect(blocks.label == "已搬砖 4 / 7 小时")
        #expect(blocks.value == "57%")
        #expect(blocks.startText == "10:00 上班")
        #expect(blocks.middleText == "12:00–13:00 干饭")
        #expect(blocks.endText == "18:00 下班")
        #expect(panel.cowScene == .working)
        #expect(panel.cowBubble.prefix == "距下班")
        #expect(panel.cowBubble.value == "3:00")
    }

    @Test("已下班：7 格全满")
    func offWork() throws {
        let panel = try #require(snapshot(of: try onboarded(), at: standardDay(18, 30)).panel)
        let blocks = try #require(panel.blocks)

        #expect(blocks.filled == 7)
        #expect(blocks.value == "100%")
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
        #expect(blocks.endText == "19:05 现在")
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
        #expect(short.startText == "10:00 开始")
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

    @Test("头图说明行：未上班几点开工、上班中每秒进账、干饭几点继续、白干每秒倒贴、休息日下个上班日几点开工")
    func heroCaption() throws {
        let state = try onboarded()
        let caption = { (now: Moment) in snapshot(of: state, at: now).panel?.heroCaption }

        #expect(caption(standardDay(9, 15)) == HeroCaption(icon: .alarm, text: "10:00 开工"))
        #expect(caption(standardDay(15, 0)) == HeroCaption(icon: .rising, text: "每秒 +¥0.0397 · 时薪 ¥142.86"))
        #expect(caption(standardDay(12, 30)) == HeroCaption(icon: .pause, text: "13:00 继续计钱"))
        #expect(caption(moment(2026, 2, 14, 10, 0)) == HeroCaption(icon: .alarm, text: "周一 10:00 开工"))
        let unpaid = try applied(.startUnpaidWork, to: state, at: standardDay(18, 0))
        #expect(snapshot(of: unpaid, at: standardDay(19, 5)).panel?.heroCaption
            == HeroCaption(icon: .falling, text: "18:00 起白干 · 每秒倒贴 ¥0.0397"))
    }

    @Test("大胆版统计行：上班中为今日扣款、本月累计 (取整带千分位)、距离周末；白干中为今日结算、今日扣款、本月累计")
    func boldStats() throws {
        let state = try onboarded()
        let working = try #require(snapshot(of: state, at: standardDay(15, 0)).panel)
        #expect(working.boldStats.map(\.title) == ["今日扣款", "本月累计", "距离周末"])
        #expect(working.boldStats[0].value == "¥0")

        let unpaid = try applied(.startUnpaidWork, to: state, at: standardDay(18, 0))
        let panel = try #require(snapshot(of: unpaid, at: standardDay(19, 5)).panel)
        #expect(panel.boldStats.map(\.title) == ["今日结算", "今日扣款", "本月累计"])
        #expect(panel.boldStats[0].value == "¥1,000")
    }

    @Test("统计行金额：取整到元、带千分位，负数前面是「−」")
    func groupedMoney() {
        #expect(Format.groupedMoney(3521.43) == "¥3,521")
        #expect(Format.groupedMoney(114380) == "¥114,380")
        #expect(Format.groupedMoney(0) == "¥0")
        #expect(StatItem.todayDeduction(50).value == "−¥50")
    }

    @Test("头图标题：上班中、未上班、干饭中、已下班、白干中、休息日被迫营业、休息日")
    func heroKicker() throws {
        let state = try onboarded()
        let kicker = { (state: AppState, now: Moment) in snapshot(of: state, at: now).panel?.heroKicker }
        #expect(kicker(state, standardDay(15, 0)) == "今天又给自己挣了")
        #expect(kicker(state, standardDay(9, 15)) == "离开工还有")
        #expect(kicker(state, standardDay(12, 30)) == "干饭不计钱，先停一下")
        #expect(kicker(state, standardDay(18, 30)) == "今天的砖搬完了")
        #expect(kicker(state, moment(2026, 2, 14, 10, 0)) == "离开工还有")
        let unpaid = try applied(.startUnpaidWork, to: state, at: standardDay(18, 0))
        #expect(kicker(unpaid, standardDay(19, 5)) == "下班了还在倒贴")
        let forced = try applied(.startUnpaidWork, to: state, at: moment(2026, 2, 14, 10, 0))
        #expect(kicker(forced, moment(2026, 2, 14, 11, 0)) == "休息日被迫营业")
    }

    @Test("头图短台词：未上班、已下班、休息日有，最长五个字；上班中没有 (气泡写倒计时)")
    func heroQuip() throws {
        let state = try onboarded()
        let quip = { (now: Moment) in snapshot(of: state, at: now).panel?.heroQuip }
        #expect(quip(standardDay(15, 0)) == nil)
        for now in [standardDay(9, 15), standardDay(18, 30), moment(2026, 2, 14, 10, 0)] {
            let text = try #require(quip(now))
            #expect(text.count <= 5)
        }
    }
}
