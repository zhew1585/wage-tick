import Foundation

/// 界面设置 (issue #1 状态清单)：牛马在菜单与设置里改的展示偏好 (PRD 4.7.2)，与引导无关，未完成引导时也有默认值。
public struct InterfaceSettings: Sendable, Equatable, Codable {
    /// 老板路过模式 (PRD 4.7.1 第 3 条)：开启时菜单栏只剩小牛。
    public internal(set) var bossMode: Bool
    /// 切换老板路过的全局快捷键，默认 ⌃⌥B【O1】。
    public internal(set) var bossModeHotkey: Hotkey
    /// 菜单栏显示模式 (PRD 4.7.1 第 2 条)，默认金额。
    public internal(set) var menuBarMode: MenuBarMode
    /// 下班通知开关 (PRD 4.7.2)，默认开。
    public internal(set) var offWorkNotification: Bool
    /// 目标达成通知开关 (PRD 4.7.2)，默认开。
    public internal(set) var goalReachedNotification: Bool

    private enum CodingKeys: String, CodingKey {
        case bossMode, bossModeHotkey, menuBarMode, offWorkNotification, goalReachedNotification
    }

    public init() {
        bossMode = false
        bossModeHotkey = Hotkey(key: "B", modifiers: [.control, .option])
        menuBarMode = .amount
        offWorkNotification = true
        goalReachedNotification = true
    }

    /// 旧文件缺少的字段 (如 #5 写出的文件没有显示模式) 取默认值，不当作损坏文件。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InterfaceSettings()
        bossMode = try container.decodeIfPresent(Bool.self, forKey: .bossMode) ?? defaults.bossMode
        bossModeHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .bossModeHotkey) ?? defaults.bossModeHotkey
        menuBarMode = try container.decodeIfPresent(MenuBarMode.self, forKey: .menuBarMode) ?? defaults.menuBarMode
        offWorkNotification = try container.decodeIfPresent(Bool.self, forKey: .offWorkNotification)
            ?? defaults.offWorkNotification
        goalReachedNotification = try container.decodeIfPresent(Bool.self, forKey: .goalReachedNotification)
            ?? defaults.goalReachedNotification
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
