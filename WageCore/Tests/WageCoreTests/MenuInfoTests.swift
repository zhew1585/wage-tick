import Foundation
import Testing
import WageCore

// 菜单栏菜单最上面的今日信息 (issue #18)：同今日概览统计行的三项；菜单栏是「仅图标」且还没下班时，最前面多一行今日已赚。
// 算例：2026-02-11 (周三)，月薪 20000、10:00 至 18:00、饭点 12:00 至 13:00，日薪 1000。

private func menuInfo(_ state: AppState, at now: Moment) -> [String] {
    snapshot(of: state, at: now).menuInfo.map { "\($0.title) \($0.value)" }
}

@Suite("菜单栏菜单的今日信息")
struct MenuInfoTests {
    @Test("上班中：距离下班、距离周末、本月累计，同统计行")
    func working() throws {
        #expect(menuInfo(try onboarded(), at: standardDay(15, 0)) == ["距离下班 3:00:00", "距离周末 3 天", "本月累计 ¥7571.43"])
    }

    @Test("已下班：今日结算、距离周末、本月累计")
    func offWork() throws {
        #expect(menuInfo(try onboarded(), at: standardDay(18, 30)) == ["今日结算 ¥1000", "距离周末 3 天", "本月累计 ¥8000"])
    }

    @Test("休息日：本月已上班、本月累计、距离周末")
    func restDay() throws {
        #expect(menuInfo(try onboarded(), at: moment(2026, 2, 14, 11, 0)) == ["本月已上班 10/20 天", "本月累计 ¥10000", "距离周末 正在休息"])
    }

    @Test("菜单栏仅图标、还没下班：最前面多一行今日已赚 (2 位小数)")
    func iconOnlyAddsEarned() throws {
        let state = try apply(.setMenuBarMode(.iconOnly), to: try onboarded(), at: standardDay(9, 0)).state
        #expect(menuInfo(state, at: standardDay(15, 0)) == ["今日已赚 ¥571.43", "距离下班 3:00:00", "距离周末 3 天", "本月累计 ¥7571.43"])
        // 已下班时统计行里已有今日结算，不再加。
        #expect(menuInfo(state, at: standardDay(18, 30)).first == "今日结算 ¥1000")
    }

    @Test("菜单栏显示金额或进度时不重复今日已赚")
    func amountModeDoesNotRepeat() throws {
        let state = try apply(.setMenuBarMode(.progress), to: try onboarded(), at: standardDay(9, 0)).state
        #expect(menuInfo(state, at: standardDay(15, 0)).first == "距离下班 3:00:00")
    }

    @Test("未完成引导：没有今日信息")
    func notOnboarded() {
        #expect(snapshot(of: AppState(), at: standardDay(15, 0)).menuInfo.isEmpty)
    }
}
