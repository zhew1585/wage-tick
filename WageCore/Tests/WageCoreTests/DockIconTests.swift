import Foundation
import Testing
@testable import WageCore

private func applied(_ command: Command, to state: AppState) throws -> AppState {
    try apply(command, to: state, at: standardDay(9, 0)).state
}

@Suite("设置：隐藏 Dock 图标")
struct DockIconTests {
    @Test("默认显示 Dock 图标")
    func shownByDefault() {
        #expect(!AppState().settings.hidesDockIcon)
    }

    @Test("引导前也能开关，开关记进界面设置")
    func toggleBeforeOnboarding() throws {
        let hidden = try applied(.setHidesDockIcon(true), to: AppState())
        #expect(hidden.settings.hidesDockIcon)
        #expect(!(try applied(.setHidesDockIcon(false), to: hidden).settings.hidesDockIcon))
    }

    @Test("存盘后读回仍是隐藏")
    func persists() throws {
        let hidden = try applied(.setHidesDockIcon(true), to: try onboarded())
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(hidden))
        #expect(restored.settings.hidesDockIcon)
    }

    @Test("没有这个字段的旧状态文件读回为显示")
    func legacyDefaultsToShown() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(try onboarded())) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any])
        settings["hidesDockIcon"] = nil
        json["settings"] = settings
        let restored = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!restored.settings.hidesDockIcon)
    }
}
