import Foundation
import Testing
import WageCore

@Suite("老板路过模式")
struct BossModeTests {
    /// 在 `now` 时刻切换一次老板路过。
    private func toggled(_ state: AppState, at now: Moment) throws -> AppState {
        try apply(.toggleBossMode, to: state, at: now).state
    }

    @Test("AC-BOSS-01 上班中开启：数字消失，小牛仍在拉磨")
    func onHidesNumberKeepsCow() throws {
        let state = try toggled(try onboarded(), at: standardDay(11, 0))

        #expect(snapshot(of: state, at: standardDay(11, 0)).menuBar == MenuBarDisplay(pose: .grinding, text: nil))
    }

    @Test("AC-BOSS-02 再按一次：恢复显示今日已赚")
    func secondToggleRestoresNumber() throws {
        let on = try toggled(try onboarded(), at: standardDay(11, 0))
        let off = try toggled(on, at: standardDay(11, 0))

        #expect(snapshot(of: off, at: standardDay(11, 0)).menuBar == MenuBarDisplay(pose: .grinding, text: "142.8571"))
    }

    @Test("AC-BOSS-04 开启 10 分钟后关闭：数字为当前时刻的今日已赚，无缺口")
    func hiddenTimeStillEarns() throws {
        let on = try toggled(try onboarded(), at: standardDay(11, 0))
        let off = try toggled(on, at: standardDay(11, 10))

        // 10:00 至 11:10 共 70 分钟，占 7 小时的 1/6：1000 ÷ 6 = 166.6667。
        #expect(snapshot(of: off, at: standardDay(11, 10)).menuBar.text == "166.6667")
    }

    @Test("PRD 4.7.2 / O1 默认关闭，快捷键默认 ⌃⌥B；引导前也有")
    func defaultsBeforeAndAfterOnboarding() throws {
        let expected = Hotkey(key: "B", modifiers: [.control, .option])

        for state in [AppState(), try onboarded()] {
            let settings = snapshot(of: state, at: standardDay(11, 0)).settings
            #expect(settings.bossMode == false)
            #expect(settings.bossModeHotkey == expected)
        }
    }

    @Test("F2 左键菜单打勾：快照给出老板路过是否开启")
    func snapshotReportsBossMode() throws {
        let state = try toggled(try onboarded(), at: standardDay(11, 0))

        #expect(snapshot(of: state, at: standardDay(11, 0)).settings.bossMode == true)
    }

    @Test("老板路过开关重启后保留：状态存成 JSON 再读回，菜单栏仍只有小牛")
    func survivesRestart() throws {
        let state = try toggled(try onboarded(), at: standardDay(11, 0))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(snapshot(of: restored, at: standardDay(11, 0)).menuBar == MenuBarDisplay(pose: .grinding, text: nil))
    }

    @Test("升级兼容：没有界面设置的旧状态文件照常读回，老板路过默认关闭")
    func oldStateWithoutSettingsDecodes() throws {
        let old = try JSONEncoder().encode(try onboarded())
        var json = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
        json["settings"] = nil
        let restored = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))

        let snap = snapshot(of: restored, at: standardDay(11, 0))
        #expect(snap.menuBar.text == "142.8571")
        #expect(snap.settings == snapshot(of: AppState(), at: standardDay(11, 0)).settings)
    }
}
