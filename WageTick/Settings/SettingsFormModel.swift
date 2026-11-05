import AppKit
import Carbon.HIToolbox
import Observation
import OSLog
import WageCore

/// 设置页某一项操作后的提示。
enum FormMessage: Equatable {
    case saved
    case error(String)
}

/// 设置页的表单状态与动作 (PRD F12)。
/// 每一项都发命令给核心，校验与提示文案来自核心的 `CommandError`，与引导一致 (PRD 4.3.5 #1 至 #3)。
/// 月薪、作息点「保存」才生效；显示模式、快捷键、开机自启、下班通知改了立即生效。
@MainActor
@Observable
final class SettingsFormModel {
    var salaryText = ""
    var scheduleDraft = ScheduleDraft(.default)
    private(set) var menuBarMode = MenuBarMode.amount
    private(set) var hotkeyText = ""
    private(set) var launchAtLogin = true
    private(set) var isRecordingHotkey = false
    private(set) var offWorkNotification = true
    /// 系统拒绝了通知权限：通知区显示提示 (AC-SET-05)。
    private(set) var notificationDenied = false

    private(set) var salaryMessage: FormMessage?
    private(set) var scheduleMessage: FormMessage?
    private(set) var hotkeyMessage: FormMessage?
    private(set) var launchMessage: FormMessage?

    @ObservationIgnored private let model: AppModel
    /// 改完设置立即重绘菜单栏；改快捷键时重新注册全局快捷键。
    @ObservationIgnored private weak var menuBar: StatusItemController?
    @ObservationIgnored private let notifier: SystemNotifier
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private let logger = Logger(subsystem: AppIdentity.bundleID, category: "Settings")

    init(model: AppModel, menuBar: StatusItemController, notifier: SystemNotifier) {
        self.model = model
        self.menuBar = menuBar
        self.notifier = notifier
    }

    /// 打开设置页时按最新快照填好各项，清掉上次的提示。
    func reload() {
        let snap = model.currentSnapshot()
        if let form = snap.settingsForm {
            salaryText = form.monthlySalaryText
            scheduleDraft = ScheduleDraft(form.schedule)
            launchAtLogin = form.launchAtLogin
        }
        menuBarMode = snap.settings.menuBarMode
        hotkeyText = snap.settings.bossModeHotkey.displayText
        offWorkNotification = snap.settings.offWorkNotification
        refreshNotificationPermission()
        salaryMessage = nil
        scheduleMessage = nil
        hotkeyMessage = nil
        launchMessage = nil
    }

    /// 改月薪，对当月整月生效。输入不是数字时按 0 交给核心，得到「月薪得是个正数」。
    func saveSalary() {
        salaryMessage = send(.changeMonthlySalary(SalaryText.parse(salaryText) ?? 0))
        if salaryMessage == .saved, let form = model.currentSnapshot().settingsForm {
            salaryText = form.monthlySalaryText
        }
    }

    /// 改作息，从今天起生效。
    func saveSchedule() {
        scheduleMessage = send(.changeSchedule(scheduleDraft.schedule))
    }

    func setMenuBarMode(_ mode: MenuBarMode) {
        guard send(.setMenuBarMode(mode)) == .saved else { return }
        menuBarMode = mode
    }

    /// 先改系统登录项，成功了才记进状态，免得开关与系统实际不一致。
    func setLaunchAtLogin(_ enabled: Bool) {
        guard LaunchAtLogin.set(enabled: enabled) else {
            launchMessage = .error("开机自启没设置成功，去系统设置的登录项里看看")
            return
        }
        launchMessage = send(.setLaunchAtLogin(enabled))
        if launchMessage == .saved { launchAtLogin = enabled }
    }

    func setOffWorkNotification(_ enabled: Bool) {
        guard send(.setOffWorkNotification(enabled)) == .saved else { return }
        offWorkNotification = enabled
    }

    func openNotificationSettings() {
        notifier.openSystemSettings()
    }

    /// 重新读一次系统通知权限：打开设置页、从系统设置切回来时调用。
    func refreshNotificationPermission() {
        Task { notificationDenied = await notifier.isDenied() }
    }

    /// 开始录制快捷键：暂停全局快捷键，接下来按下的一组键作为新快捷键，esc 取消。
    func beginRecordingHotkey() {
        guard keyMonitor == nil else { return }
        hotkeyMessage = nil
        isRecordingHotkey = true
        menuBar?.suspendBossModeHotkey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.recorded(event) }
            return nil
        }
    }

    /// 结束录制 (取消、录到了、或关掉设置页)，恢复全局快捷键。
    func endRecordingHotkey() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
        isRecordingHotkey = false
        menuBar?.resumeBossModeHotkey()
    }

    private func recorded(_ event: NSEvent) {
        endRecordingHotkey()
        let hotkey = Hotkey(event: event)
        if Int(event.keyCode) == kVK_Escape, hotkey.modifiers.isEmpty { return }
        hotkeyMessage = changeHotkey(to: hotkey)
        hotkeyText = model.currentSnapshot().settings.bossModeHotkey.displayText
    }

    /// 先校验，再在系统注册新组合，成功后才保存；注册失败时旧快捷键保持有效 (PRD 6.4)。
    private func changeHotkey(to hotkey: Hotkey) -> FormMessage {
        if let error = Validation.hotkey(hotkey) { return .error(error.message) }
        let old = model.currentSnapshot().settings.bossModeHotkey
        guard menuBar?.rebindBossModeHotkey(hotkey) == true else {
            return .error("这个快捷键被系统或别的软件占用了，换一个吧")
        }
        let result = send(.setBossModeHotkey(hotkey))
        if result != .saved, menuBar?.rebindBossModeHotkey(old) != true {
            logger.error("快捷键保存失败后换回旧组合也失败了，老板路过只能从左键菜单切换")
        }
        return result
    }

    /// 发命令并立即重绘菜单栏，返回要展示的提示。
    private func send(_ command: Command) -> FormMessage {
        do {
            try model.send(command)
        } catch {
            return .error(error.message)
        }
        menuBar?.refresh()
        return .saved
    }
}
