import Foundation
import Testing
@testable import WageCore

// 桌面悬浮小牛 (issue #21 起，现为整个 App 的形象)：按场景决定小牛姿势、气泡、存钱罐与贴边小条。
// 算例：2026-11-02 (周一) 双休完成引导，作息 10:00 至 18:00、饭点 12:00 至 13:00。
// 设了发薪日时为 15 号遇休息日提前：11 月 15 日是周日，实际发薪日 11-13 (周五)，上一个是 10-15 (周四)，周期 29 天。

private func at(_ month: Int, _ day: Int, _ hour: Int = 11, _ minute: Int = 0) -> Moment {
    moment(2026, month, day, hour, minute)
}

private func plain() throws -> AppState {
    try onboarded(at: moment(2026, 11, 2, 9, 0))
}

/// 设好发薪日 (15 号，提前) 的状态。
private func withPayday() throws -> AppState {
    try apply(.setPayday(Payday(dayOfMonth: 15, shift: .earlier)), to: plain(), at: at(11, 2)).state
}

private func applied(_ command: Command, to state: AppState, at now: Moment = at(11, 5)) throws -> AppState {
    try apply(command, to: state, at: now).state
}

private func cow(_ state: AppState, at now: Moment) throws -> FloatingCow {
    try #require(snapshot(of: state, at: now).floatingCow)
}

@Suite("桌面悬浮小牛：按日状态")
struct FloatingCowDayTests {
    @Test("未上班：打哈欠，气泡「距上班 0:45」，罐子空")
    func beforeWork() throws {
        let value = try cow(plain(), at: at(11, 5, 9, 15))
        #expect(value.scene == .beforeWork)
        #expect(value.pose == .yawning)
        #expect(value.bubble.prefix == "距上班")
        #expect(value.bubble.value == "0:45")
        #expect(value.bubble.unit == nil)
        #expect(value.bubble.numeric)
        #expect(value.bubble.style == .accent)
        #expect(value.jar == CoinJar(rows: 0, overflowing: false))
        #expect(value.pill == FloatingCowPill(value: "0:45", caption: "距上班", style: .accent))
    }

    @Test("倒计时不足一分钟按一分钟算，不显示 0:00")
    func countdownRoundsUp() throws {
        let value = try cow(plain(), at: moment(2026, 11, 5, 9, 59, 30))
        #expect(value.bubble.value == "0:01")
    }

    @Test("上班中：端咖啡，气泡「距下班 2:14」，罐子装工作进度 (4 小时 46 分 / 7 小时约 3 层)")
    func working() throws {
        let value = try cow(plain(), at: at(11, 5, 15, 46))
        #expect(value.scene == .working)
        #expect(value.pose == .working)
        #expect(value.bubble.prefix == "距下班")
        #expect(value.bubble.value == "2:14")
        #expect(value.bubble.style == .accent)
        #expect(value.jar == CoinJar(rows: 3, overflowing: false))
    }

    @Test("干饭中：捧碗，气泡「距开工 0:32」")
    func lunch() throws {
        let value = try cow(plain(), at: at(11, 5, 12, 28))
        #expect(value.scene == .lunch)
        #expect(value.pose == .eating)
        #expect(value.bubble.prefix == "距开工")
        #expect(value.bubble.value == "0:32")
    }

    @Test("请假中：晒太阳，气泡照样「距下班」")
    func onLeave() throws {
        let leave = Leave(start: TimeOfDay(hour: 14, minute: 0), end: TimeOfDay(hour: 16, minute: 0), deductionPercent: 25)
        let state = try applied(.setLeave(leave), to: plain(), at: at(11, 5, 9))
        let value = try cow(state, at: at(11, 5, 15))
        #expect(value.scene == .onLeave)
        #expect(value.pose == .sunbathing)
        #expect(value.bubble.prefix == "距下班")
        #expect(value.bubble.value == "3:00")
    }

    @Test("已下班：躺平，气泡「今天赚了」今日结算，白底 ink，罐子装满")
    func offWork() throws {
        let state = try plain()
        let snap = snapshot(of: state, at: at(11, 5, 19))
        let value = try #require(snap.floatingCow)
        let cap = try #require(snap.today?.earnings?.cap)
        #expect(value.scene == .offWork)
        #expect(value.pose == .lyingFlat)
        #expect(value.bubble.prefix == "今天赚了")
        #expect(value.bubble.value == Format.money(cap))
        #expect(value.bubble.numeric)
        #expect(value.bubble.style == .ink)
        #expect(value.jar == CoinJar(rows: CoinJar.maxRows, overflowing: false))
    }

    @Test("休息日：晒太阳，气泡「距上班 2 天」，不显示罐子")
    func restDay() throws {
        let value = try cow(plain(), at: at(11, 7))
        #expect(value.scene == .restDay)
        #expect(value.pose == .sunbathing)
        #expect(value.bubble.prefix == "距上班")
        #expect(value.bubble.value == "2")
        #expect(value.bubble.unit == "天")
        #expect(value.bubble.style == .ink)
        #expect(value.jar == nil)
        #expect(value.pill == FloatingCowPill(value: "2 天", caption: "距上班", style: .ink))
    }

    @Test("休息日第二天就上班：大字「明天」，不是数字")
    func restDayBeforeWork() throws {
        let value = try cow(plain(), at: at(11, 8))
        #expect(value.bubble.value == "明天")
        #expect(value.bubble.unit == nil)
        #expect(!value.bubble.numeric)
        #expect(value.pill == FloatingCowPill(value: "明天", caption: "距上班", style: .ink))
    }

    @Test("全天请假按休息日")
    func fullDayLeave() throws {
        let leave = Leave(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0), deductionPercent: 100)
        let state = try applied(.setLeave(leave), to: plain(), at: at(11, 5, 9))
        #expect(try cow(state, at: at(11, 5, 15)).scene == .restDay)
    }

    @Test("白干计时中：冒汗，气泡「已白干 1:23」(不足一分钟不进位)")
    func unpaidWork() throws {
        let state = try applied(.startUnpaidWork, to: plain(), at: at(11, 5, 18, 30))
        let value = try cow(state, at: moment(2026, 11, 5, 19, 53, 40))
        #expect(value.scene == .unpaidWork)
        #expect(value.pose == .sweating)
        #expect(value.bubble.prefix == "已白干")
        #expect(value.bubble.value == "1:23")
        #expect(value.bubble.style == .accent)
    }

    @Test("休息日白干：冒汗，不显示罐子")
    func unpaidWorkOnRestDay() throws {
        let state = try applied(.startUnpaidWork, to: plain(), at: at(11, 7, 10))
        let value = try cow(state, at: at(11, 7, 11))
        #expect(value.scene == .unpaidWork)
        #expect(value.jar == nil)
    }
}

@Suite("桌面悬浮小牛：发薪")
struct FloatingCowPaydayTests {
    @Test("距发薪 8 天时照常按日状态，不提发薪")
    func farFromPayday() throws {
        #expect(try cow(withPayday(), at: at(11, 5, 15, 46)).scene == .working)
    }

    @Test("上班中、距发薪 2 天：兴奋，气泡「距发薪 2 天」，罐子装发薪周期进度 (27/29 约 5 层)")
    func soonWhileWorking() throws {
        let value = try cow(withPayday(), at: at(11, 11, 15))
        #expect(value.scene == .paydaySoon(days: 2))
        #expect(value.pose == .excited)
        #expect(value.bubble.prefix == "距发薪")
        #expect(value.bubble.value == "2")
        #expect(value.bubble.unit == "天")
        #expect(value.bubble.style == .accent)
        #expect(value.jar == CoinJar(rows: 5, overflowing: false))
        #expect(value.pill == FloatingCowPill(value: "2 天", caption: "距发薪", style: .accent))
    }

    @Test("上班中、明天发薪：大字「明天」，小条「明天 / 发薪」")
    func tomorrowWhileWorking() throws {
        let value = try cow(withPayday(), at: at(11, 12, 15))
        #expect(value.scene == .paydaySoon(days: 1))
        #expect(value.bubble.value == "明天")
        #expect(value.bubble.unit == nil)
        #expect(!value.bubble.numeric)
        #expect(value.pill == FloatingCowPill(value: "明天", caption: "发薪", style: .accent))
    }

    @Test("快发薪时只顶替上班姿势：干饭、下班照常")
    func soonOnlyReplacesWorking() throws {
        let state = try withPayday()
        #expect(try cow(state, at: at(11, 12, 12, 30)).scene == .lunch)
        #expect(try cow(state, at: at(11, 12, 19)).scene == .offWork)
    }

    @Test("发薪当天：整天跳起撒钱，绿底「今天 / 发工资啦」，罐子装满并冒出来")
    func payday() throws {
        let state = try withPayday()
        for hour in [8, 11, 12, 19] {
            let value = try cow(state, at: at(11, 13, hour, 30))
            #expect(value.scene == .payday)
            #expect(value.pose == .paid)
            #expect(value.bubble.prefix == "今天")
            #expect(value.bubble.value == "发工资啦")
            #expect(!value.bubble.numeric)
            #expect(value.bubble.style == .payday)
            #expect(value.jar == CoinJar(rows: CoinJar.maxRows, overflowing: true))
            #expect(value.pill == FloatingCowPill(value: "今天", caption: "发薪", style: .payday))
        }
    }

    @Test("发薪当天白干：冒汗压过发薪")
    func unpaidWorkBeatsPayday() throws {
        let state = try applied(.startUnpaidWork, to: withPayday(), at: at(11, 13, 18, 30))
        #expect(try cow(state, at: at(11, 13, 19)).scene == .unpaidWork)
    }

    @Test("存钱罐层数 = 进度 × 5 四舍五入")
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
    private static let scenes: [CowScene] = [
        .beforeWork, .working, .lunch, .onLeave, .offWork, .restDay, .unpaidWork,
        .paydaySoon(days: 3), .paydaySoon(days: 1), .payday,
    ]

    @Test("每个场景 3 到 5 句")
    func quipCounts() {
        for scene in Self.scenes {
            #expect((3...5).contains(scene.quips.count), "\(scene)")
        }
    }

    @Test("同一场景同一天早晚、重新取快照台词不变")
    func stableWithinDay() throws {
        let state = try plain()
        let early = try cow(state, at: at(11, 5, 10, 5)).bubble.quip
        let late = try cow(state, at: at(11, 5, 17, 55)).bubble.quip
        #expect(early == late)
    }

    @Test("换天会换台词 (两周里不止一句)")
    func variesAcrossDays() throws {
        let state = try plain()
        let quips = try Set([2, 3, 4, 5, 6, 9, 10, 11, 12, 13].map { try cow(state, at: at(11, $0, 15)).bubble.quip })
        #expect(quips.count > 1)
    }

    @Test("快了的台词写出剩几天")
    func soonTemplate() {
        #expect(CowScene.paydaySoon(days: 2).quips.first == "再坚持两天，钱在路上了")
        #expect(CowScene.paydaySoon(days: 3).quips.first == "再坚持三天，钱在路上了")
    }
}

@Suite("桌面悬浮小牛：显示与开关")
struct FloatingCowVisibilityTests {
    @Test("没设发薪日也显示")
    func shownWithoutPayday() throws {
        #expect(snapshot(of: try plain(), at: at(11, 5)).floatingCow != nil)
    }

    @Test("引导前不显示")
    func hiddenBeforeOnboarding() {
        #expect(snapshot(of: AppState(), at: at(11, 5)).floatingCow == nil)
    }

    @Test("开关默认开；关掉后不显示，再打开又出现")
    func toggle() throws {
        let state = try plain()
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
        let hidden = try applied(.hideFloatingCowForToday, to: plain(), at: at(11, 5, 10))
        #expect(snapshot(of: hidden, at: moment(2026, 11, 5, 23, 59, 59)).floatingCow == nil)
        #expect(snapshot(of: hidden, at: moment(2026, 11, 6, 0, 0)).floatingCow != nil)
    }

    @Test("藏起来之后关掉再打开开关，当天又出现")
    func toggleOnClearsHide() throws {
        let hidden = try applied(.hideFloatingCowForToday, to: plain())
        let off = try applied(.setShowsFloatingCow(false), to: hidden)
        let on = try applied(.setShowsFloatingCow(true), to: off)
        #expect(snapshot(of: on, at: at(11, 5, 15)).floatingCow != nil)
    }

    @Test("开关与藏起来的日期存盘后读回不变")
    func persists() throws {
        let state = try applied(.hideFloatingCowForToday, to: applied(.setShowsFloatingCow(false), to: plain()))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        #expect(restored == state)
    }

    @Test("没有这两个字段的旧状态文件读回为开、没藏")
    func legacyDefaults() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(try plain())) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any])
        settings["showsFloatingCow"] = nil
        settings["floatingCowHiddenOn"] = nil
        json["settings"] = settings
        let restored = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.settings.showsFloatingCow)
        #expect(snapshot(of: restored, at: at(11, 5)).floatingCow != nil)
    }
}
