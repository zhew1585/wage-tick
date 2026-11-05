import AppKit
import Carbon.HIToolbox
import OSLog
import WageCore

/// 全局快捷键：App 不在前台时也能响应 (老板路过，PRD 4.7.1 第 3 条)。
/// 用 Carbon 的 `RegisterEventHotKey`，不需要辅助功能权限。
/// 注册失败时 `init` 返回 nil，牛马仍可从左键菜单切换 (PRD 6.4)。
/// 实例需在 App 整个生命周期内持有：回调通过裸指针找回它，释放后不再注销。
@MainActor
final class GlobalHotkey {
    private static let logger = Logger(subsystem: AppIdentity.bundleID, category: "GlobalHotkey")
    /// 本 App 快捷键的签名 ("WGTK")，Carbon 用它区分不同 App 注册的快捷键。
    private static let signature: OSType = 0x5747_544B

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init?(_ hotkey: Hotkey, action: @escaping @MainActor () -> Void) {
        self.action = action
        guard let keyCode = Self.keyCodes[hotkey.key] else {
            Self.logger.error("快捷键主键无法映射：\(hotkey.key, privacy: .public)")
            return nil
        }
        guard installHandler(), register(keyCode: keyCode, modifiers: Self.carbonModifiers(hotkey.modifiers)) else {
            return nil
        }
    }

    private func installHandler() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon 事件在主线程的 run loop 上分发。
                MainActor.assumeIsolated { hotkey.action() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else {
            Self.logger.error("快捷键事件处理器安装失败：\(status)")
            return false
        }
        return true
    }

    private func register(keyCode: Int, modifiers: UInt32) -> Bool {
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            Self.logger.error("全局快捷键注册失败：\(status)")
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return false
        }
        return true
    }

    private static func carbonModifiers(_ modifiers: Set<HotkeyModifier>) -> UInt32 {
        modifiers.reduce(0) { mask, modifier in
            let flag = switch modifier {
            case .control: controlKey
            case .option: optionKey
            case .shift: shiftKey
            case .command: cmdKey
            }
            return mask | UInt32(flag)
        }
    }

    /// 主键到 ANSI 键位虚拟键码，只支持字母和数字。
    private static let keyCodes: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E,
        "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J,
        "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
        "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
        "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y,
        "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]
}

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
