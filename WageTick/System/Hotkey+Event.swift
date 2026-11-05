import AppKit
import WageCore

extension Hotkey {
    /// 设置页录制快捷键：把按下的键还原成核心的快捷键描述。
    /// 字母、数字以外的主键还原成空字符串，交给核心的 `Validation.hotkey` 拦下并给出提示。
    init(event: NSEvent) {
        let key = GlobalHotkey.keyCodes.first { $0.value == Int(event.keyCode) }?.key ?? ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let pairs: [(NSEvent.ModifierFlags, HotkeyModifier)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        self.init(key: key, modifiers: Set(pairs.filter { flags.contains($0.0) }.map(\.1)))
    }
}
