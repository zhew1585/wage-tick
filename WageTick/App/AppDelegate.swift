import AppKit
import WageCore

/// 组装外壳各部件：状态存储、菜单栏条目、主菜单、引导窗口、今日概览面板、设置窗口、目标管理、历史窗口、系统通知。
/// 普通 App + 菜单栏常驻 (ADR-0005)：点 Dock 图标找回窗口，关掉所有窗口不退出，小牛继续在菜单栏跑。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: StatusItemController!
    private var onboarding: OnboardingWindowController!
    private var todayPanel: TodayPanelWindowController!
    private var holidayUpdater: HolidayUpdater!
    private var settings: SettingsWindowController!
    private var goals: GoalsWindowController!
    private var notifier: SystemNotifier!
    private var history: HistoryWindowController!
    private var mainMenu: MainMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设计稿只有浅色一套 token (`Palette`)，App 窗口固定浅色外观；菜单都是原生菜单，跟随系统深浅 (ADR-0004)。
        NSApp.appearance = NSAppearance(named: .aqua)
        model = AppModel(store: StateStore())
        // 菜单栏第一次刷新就会推进到此刻，事件出口要先接好。
        notifier = SystemNotifier { [weak self] in self?.todayPanel.show() }
        model.onEvents = { [weak self] events in self?.notifier.post(events) }
        // 先交出内置与缓存的节假日数据，菜单栏第一次刷新就按它计算。
        holidayUpdater = HolidayUpdater(model: model)
        holidayUpdater.start()
        goals = GoalsWindowController(model: model)
        todayPanel = TodayPanelWindowController(
            model: model,
            navigation: PanelNavigation(
                openHistory: { [weak self] in self?.history.show() },
                openGoals: { [weak self] in self?.goals.show() },
                openSettings: { [weak self] in self?.settings.show() }
            )
        ) { [weak self] in
            self?.statusItem.refresh()
        }
        // 引导第 3 步完成后在引导窗口原位打开今日概览，不让界面凭空消失，也不跳位置。
        onboarding = OnboardingWindowController(model: model) { [weak self] frame in
            self?.statusItem.refresh()
            self?.todayPanel.show(replacing: frame)
        }
        statusItem = StatusItemController(
            model: model,
            openOnboarding: { [weak self] in self?.onboarding.show() },
            openTodayPanel: { [weak self] in self?.todayPanel.show() },
            openSettings: { [weak self] in self?.settings.show() },
            openGoals: { [weak self] in self?.goals.show() },
            openHistory: { [weak self] in self?.history.show() }
        )
        history = HistoryWindowController(model: model) { [weak self] in
            self?.statusItem.refresh()
        }
        settings = SettingsWindowController(form: SettingsFormModel(model: model, menuBar: statusItem, notifier: notifier))
        mainMenu = MainMenu(actions: MainMenu.Actions(
            isOnboarded: { [weak self] in self?.model.isOnboarded == true },
            openTodayPanel: { [weak self] in self?.todayPanel.show() },
            openGoals: { [weak self] in self?.goals.show() },
            openHistory: { [weak self] in self?.history.show() },
            openSettings: { [weak self] in self?.settings.show() }
        ))
        mainMenu.install()
        if !model.isOnboarded {
            onboarding.show()
        }
    }

    /// 点 Dock 图标：已引导打开今日概览，未引导回到引导。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.isOnboarded {
            todayPanel.show()
        } else {
            onboarding.show()
        }
        return false
    }

    /// 关掉所有窗口不退出，菜单栏小牛继续跑；只有菜单里的「退出」(⌘Q) 才退出。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
