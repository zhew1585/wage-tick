import Foundation

/// 界面设置 (issue #1 状态清单)：牛马在菜单与设置里改的展示偏好 (PRD 4.7.2)，与引导无关，未完成引导时也有默认值。
public struct InterfaceSettings: Sendable, Equatable, Codable {
    /// 菜单栏显示模式 (PRD 4.7.1 第 2 条)，默认金额。
    public internal(set) var menuBarMode: MenuBarMode
    /// 面板目标区是否展开排队中目标 (PRD F9)，会被记住，首次默认收起【O3】。
    public internal(set) var goalQueueExpanded: Bool
    /// 下班通知开关 (PRD 4.7.2)，默认开。
    public internal(set) var offWorkNotification: Bool
    /// 目标达成通知开关 (PRD 4.7.2)，默认开。
    public internal(set) var goalReachedNotification: Bool

    private enum CodingKeys: String, CodingKey {
        case menuBarMode, goalQueueExpanded, offWorkNotification, goalReachedNotification
    }

    public init() {
        menuBarMode = .amount
        goalQueueExpanded = false
        offWorkNotification = true
        goalReachedNotification = true
    }

    /// 旧文件缺少的字段 (如 #5 写出的文件没有显示模式) 取默认值，不当作损坏文件；
    /// 已去掉的老板路过留下的 `bossMode`、`bossModeHotkey` 不在 `CodingKeys` 里，读时直接忽略，下次保存即消失。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = InterfaceSettings()
        menuBarMode = try container.decodeIfPresent(MenuBarMode.self, forKey: .menuBarMode) ?? defaults.menuBarMode
        goalQueueExpanded = try container.decodeIfPresent(Bool.self, forKey: .goalQueueExpanded) ?? defaults.goalQueueExpanded
        offWorkNotification = try container.decodeIfPresent(Bool.self, forKey: .offWorkNotification)
            ?? defaults.offWorkNotification
        goalReachedNotification = try container.decodeIfPresent(Bool.self, forKey: .goalReachedNotification)
            ?? defaults.goalReachedNotification
    }
}
