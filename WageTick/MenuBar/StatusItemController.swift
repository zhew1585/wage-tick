import AppKit
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
    private let openGoals: () -> Void
    private let openHistory: () -> Void
    private let installUpdate: () -> Void
    /// 更新已下载好、用户选了稍后时挂在菜单最上面的「重启以完成更新」及其分隔线 (ADR-0007)。
    private var updateItems: [NSMenuItem] = []
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timer: Timer?
    private var shown: MenuBarDisplay?

    init(
        model: AppModel,
        openOnboarding: @escaping () -> Void,
        openTodayPanel: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openGoals: @escaping () -> Void,
        openHistory: @escaping () -> Void,
        installUpdate: @escaping () -> Void
    ) {
        self.model = model
        self.openOnboarding = openOnboarding
        self.openTodayPanel = openTodayPanel
        self.openSettings = openSettings
        self.openGoals = openGoals
        self.openHistory = openHistory
        self.installUpdate = installUpdate
        super.init()
        configureButton()
        buildMenu()
        observeClockChanges()
        refresh()
    }

    /// 左键菜单：macOS 原生菜单，系统画标题、快捷键、勾选与分隔线，跟随系统深浅色，不放图标。
    /// 项目与快捷键按 PRD F2：今日概览 ⌘1、目标 ⌘2、历史 ⌘3 | 设置… ⌘, | 退出 ⌘Q。
    /// 有等重启的更新时最上面多一项「重启以完成更新」(`setPendingUpdate`)。
    private func buildMenu() {
        addRow("今日概览", key: "1", action: #selector(todayPanelClicked))
        addRow("目标", key: "2", action: #selector(goalsClicked))
        addRow("历史", key: "3", action: #selector(historyClicked))
        menu.addItem(.separator())
        addRow("设置…", key: ",", action: #selector(settingsClicked))
        menu.addItem(.separator())
        addRow("退出", key: "q", action: #selector(NSApplication.terminate(_:)), target: NSApp)
    }

    /// 有下载好、等重启的更新时在菜单最上面加「重启以完成更新（0.1.1）」，装完或没有时去掉。
    func setPendingUpdate(_ version: String?) {
        updateItems.forEach(menu.removeItem)
        updateItems = []
        guard let version else { return }
        let install = NSMenuItem(title: "重启以完成更新（\(version)）", action: #selector(installUpdateClicked), keyEquivalent: "")
        install.target = self
        updateItems = [install, .separator()]
        for (index, item) in updateItems.enumerated() {
            menu.insertItem(item, at: index)
        }
    }

    private func addRow(_ title: String, key: String, action: Selector, target: AnyObject? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        menu.addItem(item)
    }

    /// 取最新快照更新菜单栏，并按日状态安排下一次刷新。
    func refresh() {
        let snap = model.currentSnapshot()
        // 引导完成前没有菜单，点击直接走 `buttonClicked`。
        item.menu = model.isOnboarded ? menu : nil
        render(snap.menuBar)
        scheduleNextRefresh(rolling: snap.today?.isRolling == true)
    }

    private func configureButton() {
        guard let button = item.button else { return }
        button.imagePosition = .imageLeading
        // 设计稿 F2：数字用 JetBrains Mono 13/500，等宽不抖。
        button.font = AppFont.nsFont(.num, size: 13, weight: .medium)
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

    @objc private func todayPanelClicked() {
        openTodayPanel()
    }

    @objc private func settingsClicked() {
        openSettings()
    }

    @objc private func goalsClicked() {
        openGoals()
    }

    @objc private func historyClicked() {
        openHistory()
    }

    @objc private func installUpdateClicked() {
        installUpdate()
    }
}
