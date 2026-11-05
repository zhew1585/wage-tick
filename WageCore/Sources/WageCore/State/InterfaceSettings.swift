import Foundation

/// 界面设置 (issue #1 状态清单)：牛马在菜单与设置里改的展示偏好 (PRD 4.7.2)，与引导无关，未完成引导时也有默认值。
public struct InterfaceSettings: Sendable, Equatable, Codable {
    /// 老板路过模式 (PRD 4.7.1 第 3 条)：开启时菜单栏只剩小牛。
    public internal(set) var bossMode: Bool
    /// 切换老板路过的全局快捷键，默认 ⌃⌥B【O1】。
    public internal(set) var bossModeHotkey: Hotkey

    public init() {
        bossMode = false
        bossModeHotkey = Hotkey(key: "B", modifiers: [.control, .option])
    }
}

/// 与平台无关的快捷键描述，由外壳映射成系统的按键码与修饰键。
public struct Hotkey: Sendable, Equatable, Codable {
    /// 主键，单个大写字母或数字，如 "B"。
    public let key: String
    public let modifiers: Set<HotkeyModifier>

    public init(key: String, modifiers: Set<HotkeyModifier>) {
        self.key = key
        self.modifiers = modifiers
    }
}

public enum HotkeyModifier: String, Sendable, Codable, CaseIterable {
    case control, option, shift, command
}
