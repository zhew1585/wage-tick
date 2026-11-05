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
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timer: Timer?
    private var shown: MenuBarDisplay?

    init(model: AppModel, openOnboarding: @escaping () -> Void) {
        self.model = model
        self.openOnboarding = openOnboarding
        super.init()
        configureButton()
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        observeClockChanges()
        refresh()
    }

    /// 取最新快照更新菜单栏，并按日状态安排下一次刷新。
    func refresh() {
        let snap = model.currentSnapshot()
        // 引导完成前没有菜单，点击直接走 `buttonClicked`。
        item.menu = model.isOnboarded ? menu : nil
        render(snap.menuBar)
        scheduleNextRefresh(rolling: snap.today?.status == .working)
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
}
