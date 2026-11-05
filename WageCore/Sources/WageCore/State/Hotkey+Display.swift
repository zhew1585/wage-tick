import Foundation

extension Hotkey {
    /// 设置页展示的快捷键，修饰键按系统惯例 ⌃⌥⇧⌘ 排在主键前，如「⌃⌥B」。
    public var displayText: String {
        let symbols: [(HotkeyModifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key
    }
}
