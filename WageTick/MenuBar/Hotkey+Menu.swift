import AppKit
import WageCore

extension Hotkey {
    /// 菜单项上的按键与修饰键：菜单展开时按下即触发，`MenuRowView` 据此画出 ⌃⌥B 这样的符号。
    var menuKeyEquivalent: String { key.lowercased() }

    var menuModifierMask: NSEvent.ModifierFlags {
        modifiers.reduce(into: []) { mask, modifier in
            switch modifier {
            case .control: mask.insert(.control)
            case .option: mask.insert(.option)
            case .shift: mask.insert(.shift)
            case .command: mask.insert(.command)
            }
        }
    }
}
