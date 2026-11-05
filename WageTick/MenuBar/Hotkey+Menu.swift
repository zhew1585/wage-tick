import AppKit
import WageCore

extension Hotkey {
    /// 菜单项上显示用的按键与修饰键，由系统渲染成 ⌃⌥B 这样的符号。
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
