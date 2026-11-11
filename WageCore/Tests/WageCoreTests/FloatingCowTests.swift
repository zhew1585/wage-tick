import Foundation
import Testing
@testable import WageCore

// 桌面悬浮小牛 (issue #21)：按距发薪分心情档位，决定小牛姿势、气泡、存钱罐与贴边小条。
// 算例：2026-11-02 (周一) 双休完成引导，发薪日 15 号遇休息日提前。
// 11 月 15 日是周日，实际发薪日 11-13 (周五)；上一个是 10-15 (周四)，周期 29 天。

private func at(_ month: Int, _ day: Int, _ hour: Int = 11) -> Moment { moment(2026, month, day, hour, 0) }

/// 设好发薪日 (15 号，提前) 的状态。
private func withPayday() throws -> AppState {
    let state = try onboarded(at: moment(2026, 11, 2, 9, 0))
    return try apply(.setPayday(Payday(dayOfMonth: 15, shift: .earlier)), to: state, at: at(11, 2)).state
}

private func applied(_ command: Command, to state: AppState, at now: Moment = at(11, 5)) throws -> AppState {
    try apply(command, to: state, at: now).state
}

private func cow(_ state: AppState, at now: Moment) throws -> FloatingCow {
    try #require(snapshot(of: state, at: now).floatingCow)
}

@Suite("桌面悬浮小牛：心情档位")
struct FloatingCowMoodTests {
    @Test("验收算例：11-05 距发薪 8 天，一周左右、打工，数字 accent，罐子 72% 约 4 层")
    func acceptanceExample() throws {
        let value = try cow(withPayday(), at: at(11, 5))
        #expect(value.mood == .withinTwoWeeks)
        #expect(value.pose == .working)
        #expect(value.bubble.prefix == "距发薪")
        #expect(value.bubble.value == "8")
        #expect(value.bubble.unit == "天")
        #expect(value.bubble.style == .accent)
        #expect(value.jar.rows == 4)
        #expect(!value.jar.overflowing)
        #expect(value.pill == FloatingCowPill(value: "8 天", caption: "距发薪", style: .accent))
    }

    @Test("各档位按距发薪天数切换", arguments: [
        // (月, 日, 档位)：10-16 至 10-18 刚发完；10-19 起 > 14 天为还早；10-30 剩 14 天进入一周左右。
        (10, 16, PaydayMood.justPaid), (10, 18, .justPaid), (10, 19, .farOff), (10, 29, .farOff),
        (10, 30, .withinTwoWeeks), (11, 9, .withinTwoWeeks), (11, 10, .soon), (11, 11, .soon),
        (11, 12, .tomorrow), (11, 13, .payday),
    ])
    func tiers(month: Int, day: Int, mood: PaydayMood) throws {
        #expect(try cow(withPayday(), at: at(month, day)).mood == mood)
    }

    @Test("姿势：还早、一周左右、刚发完打工，快了、明天兴奋，当天发薪")
    func poses() {
        #expect(PaydayMood.farOff.pose == .working)
        #expect(PaydayMood.withinTwoWeeks.pose == .working)
        #expect(PaydayMood.justPaid.pose == .working)
        #expect(PaydayMood.soon.pose == .excited)
        #expect(PaydayMood.tomorrow.pose == .excited)
        #expect(PaydayMood.payday.pose == .paid)
    }

    @Test("还早：白底，数字 ink")
    func farOffBubble() throws {
        let value = try cow(withPayday(), at: at(10, 22))
        #expect(value.bubble.value == "22")
        #expect(value.bubble.style == .ink)
        #expect(value.pill.style == .ink)
    }

    @Test("明天：大字「明天」不带单位，小条「明天 / 发薪」")
    func tomorrowBubble() throws {
        let value = try cow(withPayday(), at: at(11, 12))
        #expect(value.bubble.prefix == "距发薪")
        #expect(value.bubble.value == "明天")
        #expect(value.bubble.unit == nil)
        #expect(value.bubble.style == .accent)
        #expect(value.pill == FloatingCowPill(value: "明天", caption: "发薪", style: .accent))
    }

    @Test("当天：绿底「今天 / 发工资啦」，罐子装满并冒出来")
    func paydayBubble() throws {
        let value = try cow(withPayday(), at: at(11, 13))
        #expect(value.bubble.prefix == "今天")
        #expect(value.bubble.value == "发工资啦")
        #expect(value.bubble.unit == nil)
        #expect(value.bubble.style == .payday)
        #expect(value.jar == CoinJar(rows: CoinJar.maxRows, overflowing: true))
        #expect(value.pill == FloatingCowPill(value: "今天", caption: "发薪", style: .payday))
    }

    @Test("刚发完：白底数字 ink，罐子空")
    func justPaidBubble() throws {
        let value = try cow(withPayday(), at: at(10, 16))
        #expect(value.bubble.value == "28")
        #expect(value.bubble.style == .ink)
        #expect(value.jar.rows == 0)
    }

    @Test("存钱罐层数 = 周期进度 × 5 四舍五入")
    func jarRows() {
        #expect(CoinJar(progress: 0).rows == 0)
        #expect(CoinJar(progress: Decimal(25) / 100).rows == 1)
        #expect(CoinJar(progress: Decimal(21) / 29).rows == 4)
        #expect(CoinJar(progress: Decimal(28) / 29).rows == 5)
        #expect(CoinJar(progress: 1).rows == 5)
    }
}

@Suite("桌面悬浮小牛：台词")
struct FloatingCowQuipTests {
    @Test("每档 3 到 5 句，第一句是 issue 表里的示例")
    func quipCounts() {
        for mood in PaydayMood.allCases {
            #expect((3...5).contains(mood.quipCount))
        }
    }

    @Test("同一天早晚、重新取快照台词不变")
    func stableWithinDay() throws {
        let state = try withPayday()
        let morning = try cow(state, at: at(11, 5, 8)).bubble.quip
        let night = try cow(state, at: moment(2026, 11, 5, 23, 59)).bubble.quip
        #expect(morning == night)
    }

    @Test("换天会换台词 (一档两周里不止一句)")
    func variesAcrossDays() throws {
        let state = try withPayday()
        let quips = try Set((19...31).map { try cow(state, at: at(10, $0)).bubble.quip })
        #expect(quips.count > 1)
    }

    @Test("带日期的台词：一周左右写出实际发薪日与星期，快了写出剩几天")
    func quipTemplates() {
        #expect(PaydayMood.withinTwoWeeks.quips(for: PaydayCountdownSample.nov5).first == "撑住，13 号周五就发钱")
        #expect(PaydayMood.soon.quips(for: PaydayCountdownSample.nov11).first == "再坚持两天，钱在路上了")
    }
}

/// 直接构造距发薪，用来检查带日期的台词模板。
private enum PaydayCountdownSample {
    static let nov5 = PaydayCountdown(days: 8, next: LocalDate(year: 2026, month: 11, day: 13), previous: LocalDate(year: 2026, month: 10, day: 15))
    static let nov11 = PaydayCountdown(days: 2, next: LocalDate(year: 2026, month: 11, day: 13), previous: LocalDate(year: 2026, month: 10, day: 15))
}

@Suite("桌面悬浮小牛：显示与开关")
struct FloatingCowVisibilityTests {
    @Test("没设发薪日不显示")
    func hiddenWithoutPayday() throws {
        #expect(snapshot(of: try onboarded(at: at(11, 2)), at: at(11, 5)).floatingCow == nil)
    }

    @Test("开关默认开；关掉后不显示，再打开又出现")
    func toggle() throws {
        let state = try withPayday()
        #expect(state.settings.showsFloatingCow)
        let off = try applied(.setShowsFloatingCow(false), to: state)
        #expect(!off.settings.showsFloatingCow)
        #expect(snapshot(of: off, at: at(11, 5)).floatingCow == nil)
        let on = try applied(.setShowsFloatingCow(true), to: off)
        #expect(snapshot(of: on, at: at(11, 5)).floatingCow != nil)
    }

    @Test("引导前也能开关")
    func toggleBeforeOnboarding() throws {
        #expect(!(try applied(.setShowsFloatingCow(false), to: AppState()).settings.showsFloatingCow))
    }

    @Test("今天先藏起来：当天不显示，到第二天 0 点再出现")
    func hideForToday() throws {
        let hidden = try applied(.hideFloatingCowForToday, to: withPayday(), at: at(11, 5, 10))
        #expect(snapshot(of: hidden, at: moment(2026, 11, 5, 23, 59, 59)).floatingCow == nil)
        #expect(snapshot(of: hidden, at: moment(2026, 11, 6, 0, 0)).floatingCow != nil)
    }

    @Test("藏起来之后关掉再打开开关，当天又出现")
    func toggleOnClearsHide() throws {
        let hidden = try applied(.hideFloatingCowForToday, to: withPayday())
        let off = try applied(.setShowsFloatingCow(false), to: hidden)
        let on = try applied(.setShowsFloatingCow(true), to: off)
        #expect(snapshot(of: on, at: at(11, 5, 15)).floatingCow != nil)
    }

    @Test("开关与藏起来的日期存盘后读回不变")
    func persists() throws {
        let state = try applied(.hideFloatingCowForToday, to: applied(.setShowsFloatingCow(false), to: withPayday()))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        #expect(restored == state)
    }

    @Test("没有这两个字段的旧状态文件读回为开、没藏")
    func legacyDefaults() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(try withPayday())) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any])
        settings["showsFloatingCow"] = nil
        settings["floatingCowHiddenOn"] = nil
        json["settings"] = settings
        let restored = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.settings.showsFloatingCow)
        #expect(snapshot(of: restored, at: at(11, 5)).floatingCow != nil)
    }
}
