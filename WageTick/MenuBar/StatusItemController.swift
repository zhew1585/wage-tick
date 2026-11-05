import AppKit
import OSLog
import WageCore

/// 菜单栏条目：小牛 + 数字，内容完全取自快照的 `menuBar`，不自行拼接任何文字 (AC-BAR-06)。
/// 未完成引导时点击回到引导；完成后左右键弹出同一个菜单【D10】。
@MainActor
final class StatusItemController: NSObject {
    /// 上班中刷新间隔：足够让 4 位小数肉眼连续变化 (AC-BAR-02)。
    private static let rollingInterval: TimeInterval = 0.1
    /// 其他日状态数字不动，只需及时发现状态切换。
    private static let idleInterval: TimeInterval = 1

    private let model: AppModel
    private let openOnboarding: () -> Void
    private let openTodayPanel: () -> Void
    private let openSettings: () -> Void
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let bossModeItem = NSMenuItem(title: "老板路过", action: #selector(bossModeClicked), keyEquivalent: "")
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "StatusItem")
    private var timer: Timer?
    private var shown: MenuBarDisplay?
    /// 注册失败时为 nil，只能从左键菜单切换 (PRD 6.4)。
    private var bossModeHotkey: GlobalHotkey?
    /// 设置页正在录制新快捷键，期间全局快捷键保持暂停，菜单合上也不恢复。
    private var isRecordingHotkey = false

    init(
        model: AppModel,
        openOnboarding: @escaping () -> Void,
        openTodayPanel: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        self.model = model
        self.openOnboarding = openOnboarding
        self.openTodayPanel = openTodayPanel
        self.openSettings = openSettings
        super.init()
        configureButton()
        bossModeItem.target = self
        menu.delegate = self
        menu.addItem(withTitle: "今日概览", action: #selector(todayPanelClicked), keyEquivalent: "1").target = self
        menu.addItem(bossModeItem)
        menu.addItem(withTitle: "设置…", action: #selector(settingsClicked), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        registerBossModeHotkey()
        observeClockChanges()
        refresh()
    }

    /// 取最新快照更新菜单栏，并按日状态安排下一次刷新。
    func refresh() {
        let snap = model.currentSnapshot()
        // 引导完成前没有菜单，点击直接走 `buttonClicked`。
        item.menu = model.isOnboarded ? menu : nil
        render(snap.menuBar)
        renderBossModeItem(snap.settings)
        scheduleNextRefresh(rolling: snap.today?.isEarning == true)
    }

    private func configureButton() {
        guard let button = item.button else { return }
        button.imagePosition = .imageLeading
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func render(_ display: MenuBarDisplay) {
        guard display != shown, let button = item.button else { return }
        shown = display
        button.image = CowIcon.image(for: display.pose)
        button.title = display.text ?? ""
        button.imagePosition = display.text == nil ? .imageOnly : .imageLeading
    }

    /// 老板路过菜单项：开启时打勾，右侧显示当前快捷键 (F2)。
    /// 全局快捷键注册失败时不显示快捷键，免得牛马以为按了有用。
    private func renderBossModeItem(_ settings: InterfaceSettings) {
        bossModeItem.state = settings.bossMode ? .on : .off
        let hotkey = bossModeHotkey == nil ? nil : settings.bossModeHotkey
        bossModeItem.keyEquivalent = hotkey?.menuKeyEquivalent ?? ""
        bossModeItem.keyEquivalentModifierMask = hotkey?.menuModifierMask ?? []
    }

    /// 切换老板路过并立即重绘，不等下一次定时刷新 (F3：必须一键生效)。
    private func toggleBossMode() {
        do {
            try model.send(.toggleBossMode)
        } catch {
            logger.error("切换老板路过失败：\(error.message, privacy: .public)")
        }
        refresh()
    }

    private func registerBossModeHotkey() {
        bossModeHotkey = makeBossModeHotkey(model.currentSnapshot().settings.bossModeHotkey)
    }

    private func makeBossModeHotkey(_ hotkey: Hotkey) -> GlobalHotkey? {
        GlobalHotkey(hotkey) { [weak self] in
            // 引导前菜单栏本就只有小牛，切换了也看不到，忽略，免得引导完数字莫名被藏。
            guard let self, self.model.isOnboarded else { return }
            self.toggleBossMode()
        }
    }

    private func scheduleNextRefresh(rolling: Bool) {
        timer?.invalidate()
        let timer = Timer(timeInterval: rolling ? Self.rollingInterval : Self.idleInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // common 模式：菜单展开时也继续刷新。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 睡眠恢复、改系统时间、切时区后立即按当前时刻刷新 (PRD 4.3.5 #11、#14)。
    private func observeClockChanges() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(clockChanged), name: NSWorkspace.didWakeNotification, object: nil)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(clockChanged), name: .NSSystemClockDidChange, object: nil)
        center.addObserver(self, selector: #selector(clockChanged), name: .NSSystemTimeZoneDidChange, object: nil)
    }

    @objc private func clockChanged() {
        NSTimeZone.resetSystemTimeZone()
        refresh()
    }

    @objc private func buttonClicked() {
        openOnboarding()
    }

    @objc private func bossModeClicked() {
        toggleBossMode()
    }

    @objc private func todayPanelClicked() {
        openTodayPanel()
    }

    @objc private func settingsClicked() {
        openSettings()
    }
}

/// 设置页改老板路过快捷键 (#5 遗留)：录制期间暂停全局快捷键，免得按下当前组合直接切换了老板路过；
/// 新组合在系统注册成功后才保存，旧的同时失效。
extension StatusItemController {
    func suspendBossModeHotkey() {
        isRecordingHotkey = true
        bossModeHotkey?.suspend()
    }

    func resumeBossModeHotkey() {
        isRecordingHotkey = false
        bossModeHotkey?.resume()
    }

    /// 换成新组合，返回是否注册成功；失败时旧组合保持有效。
    /// 启动时注册失败过 (没有实例) 的，用新组合重新建一个。
    func rebindBossModeHotkey(_ hotkey: Hotkey) -> Bool {
        if let bossModeHotkey {
            return bossModeHotkey.rebind(to: hotkey)
        }
        bossModeHotkey = makeBossModeHotkey(hotkey)
        return bossModeHotkey != nil
    }
}

/// 菜单展开期间注销全局快捷键，让这组按键作为普通按键交给菜单项的快捷键处理；
/// 合上后再注册。这样任何时候按一次只走一条路，只切换一次。
extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        bossModeHotkey?.suspend()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard !isRecordingHotkey else { return }
        bossModeHotkey?.resume()
    }
}
