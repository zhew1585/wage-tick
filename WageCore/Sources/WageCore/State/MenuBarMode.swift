import Foundation

/// 菜单栏显示模式 (PRD 4.7.1 第 2 条)：牛马在设置里选的常态隐私程度。
public enum MenuBarMode: String, Sendable, Codable, CaseIterable {
    /// 金额 (默认)：4 位小数的今日已赚，休息日不显示数字。
    case amount
    /// 进度：工作进度百分比，休息日不显示数字。
    case progress
    /// 仅图标：只显示小牛。
    case iconOnly

    /// 设置页的选项文案。
    public var label: String {
        switch self {
        case .amount: "金额"
        case .progress: "进度"
        case .iconOnly: "仅图标"
        }
    }
}
