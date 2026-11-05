import Carbon.HIToolbox
import OSLog
import WageCore

/// 全局快捷键：App 不在前台时也能响应 (老板路过，PRD 4.7.1 第 3 条)。
/// 用 Carbon 的 `RegisterEventHotKey`，不需要辅助功能权限。
/// 首次注册失败时 `init` 返回 nil，牛马仍可从左键菜单切换 (PRD 6.4)。
/// 实例需在 App 整个生命周期内持有：回调通过裸指针找回它，释放后不再注销。
/// 改快捷键时用 `rebind(to:)` 换组合，处理器不变。
@MainActor
final class GlobalHotkey {
    private static let logger = Logger(subsystem: AppIdentity.bundleID, category: "GlobalHotkey")
    /// 本 App 快捷键的签名 ("WGTK")，Carbon 用它区分不同 App 注册的快捷键。
    private static let signature: OSType = 0x5747_544B

    private var keyCode: UInt32
    private var modifiers: UInt32
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init?(_ hotkey: Hotkey, action: @escaping @MainActor () -> Void) {
        guard let keyCode = Self.keyCodes[hotkey.key] else {
            Self.logger.error("快捷键主键无法映射：\(hotkey.key, privacy: .public)")
            return nil
        }
        self.keyCode = UInt32(keyCode)
        modifiers = Self.carbonModifiers(hotkey.modifiers)
        self.action = action
        guard installHandler() else { return nil }
        resume()
        guard hotKeyRef != nil else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    /// 暂时注销，让这组按键交给前台 (如展开的菜单) 处理。
    func suspend() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    /// 重新注册；失败只记日志，此后只能从左键菜单切换。
    func resume() {
        guard hotKeyRef == nil else { return }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            hotKeyRef = nil
            Self.logger.error("全局快捷键注册失败：\(status)")
        }
    }

    /// 换成新组合 (设置页改快捷键)：先注销旧的，再注册新的。
    /// 新组合注册失败 (如被别的软件占用) 时换回旧组合并返回 false。暂停中调用也会立即注册。
    func rebind(to hotkey: Hotkey) -> Bool {
        guard let newKeyCode = Self.keyCodes[hotkey.key] else { return false }
        let old = (keyCode: keyCode, modifiers: modifiers)
        suspend()
        keyCode = UInt32(newKeyCode)
        modifiers = Self.carbonModifiers(hotkey.modifiers)
        resume()
        guard hotKeyRef == nil else { return true }
        (keyCode, modifiers) = old
        resume()
        return false
    }

    /// 安装一次即可：只有本 App 注册的快捷键才会把事件发到这里，注销期间不会触发。
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

    /// 主键到 ANSI 键位虚拟键码，只支持字母和数字。设置页录制快捷键时也用它反查主键。
    nonisolated static let keyCodes: [String: Int] = [
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
