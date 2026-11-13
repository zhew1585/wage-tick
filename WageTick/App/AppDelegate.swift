import AppKit
import WageCore

/// 组装外壳各部件：状态存储、菜单栏条目、主菜单、引导窗口、今日概览面板 (历史、目标、设置在它里面推进来)、系统通知、桌面悬浮小牛。
/// 普通 App + 菜单栏常驻 (ADR-0005)：点 Dock 图标找回窗口，关掉所有窗口不退出，小牛继续在菜单栏跑。
/// 设置里可以隐藏 Dock 图标 (`DockIcon`)，这时只从菜单栏小牛找回窗口。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: StatusItemController!
    private var onboarding: OnboardingWindowController!
    private var todayPanel: TodayPanelWindowController!
    private var holidayUpdater: HolidayUpdater!
    private var notifier: SystemNotifier!
    private var mainMenu: MainMenu!
    private var updater: AppUpdater!
    private var floatingCow: FloatingCowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设计稿只有浅色一套 token (`Palette`)，App 窗口固定浅色外观；菜单都是原生菜单，跟随系统深浅 (ADR-0004)。
        NSApp.appearance = NSAppearance(named: .aqua)
        FieldEditorTheme.install()
        model = AppModel(store: StateStore(), widgets: WidgetBridge())
        // 牛马在设置里隐藏了 Dock 图标时，先切成只在菜单栏常驻，再开窗口。
        DockIcon.apply(hidden: model.currentSnapshot().settings.hidesDockIcon)
        // 菜单栏第一次刷新就会推进到此刻，事件出口要先接好。
        notifier = SystemNotifier { [weak self] in self?.todayPanel.show() }
        model.onEvents = { [weak self] events in
            self?.notifier.post(events)
            self?.floatingCow?.react(to: events)
        }
        model.onCommand = { [weak self] command in self?.floatingCow?.react(to: command) }
        // 先交出内置与缓存的节假日数据，菜单栏第一次刷新就按它计算。
        holidayUpdater = HolidayUpdater(model: model)
        holidayUpdater.start()
        updater = AppUpdater()

        // 引导最后一步 (作息) 完成后在引导窗口原位打开今日概览，不让界面凭空消失，也不跳位置。
        onboarding = OnboardingWindowController(model: model) { [weak self] frame in
            self?.statusItem.refresh()
            self?.todayPanel.show(replacing: frame)
        }
        statusItem = StatusItemController(
            model: model,
            openOnboarding: { [weak self] in self?.onboarding.show() },
            openTodayPanel: { [weak self] in self?.todayPanel.show() },
            openSettings: { [weak self] in self?.todayPanel.show(page: .settings) },
            openGoals: { [weak self] in self?.todayPanel.show(page: .goals) },
            openHistory: { [weak self] in self?.todayPanel.show(page: .history) },
            installUpdate: { [weak self] in self?.updater.installPendingUpdate() }
        )
        updater.onPendingVersionChange = { [weak self] version in self?.statusItem.setPendingUpdate(version) }
        // 悬浮小牛跟着菜单栏的刷新走：设置里改了开关、发薪日后菜单栏立即刷新，浮窗也随之出现或收起。
        floatingCow = FloatingCowController(model: model, actions: FloatingCowController.Actions(
            openTodayPanel: { [weak self] in self?.todayPanel.show() },
            openSettings: { [weak self] in self?.todayPanel.show(page: .settings) },
            stateChanged: { [weak self] in self?.statusItem.refresh() }
        ))
        statusItem.onSnapshot = { [weak self] snapshot in self?.floatingCow.update(snapshot) }
        statusItem.refresh()
        // 历史、目标、设置都在今日概览窗口里推进来 (`PanelPage`)。
        let pages = PanelPages(
            history: HistoryPage(model: model) { [weak self] in self?.statusItem.refresh() },
            goals: GoalsPage(model: model),
            settings: SettingsPage(
                form: SettingsFormModel(model: model, menuBar: statusItem, notifier: notifier),
                updater: updater
            )
        )
        todayPanel = TodayPanelWindowController(model: model, pages: pages) { [weak self] in
            self?.statusItem.refresh()
        }
        mainMenu = MainMenu(actions: MainMenu.Actions(
            isOnboarded: { [weak self] in self?.model.isOnboarded == true },
            openTodayPanel: { [weak self] in self?.todayPanel.show() },
            openGoals: { [weak self] in self?.todayPanel.show(page: .goals) },
            openHistory: { [weak self] in self?.todayPanel.show(page: .history) },
            openSettings: { [weak self] in self?.todayPanel.show(page: .settings) },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() }
        ))
        mainMenu.install()
        if !model.isOnboarded {
            onboarding.show()
        } else if !LaunchSource.isLoginItem {
            // 牛马自己打开 (双击、Spotlight、清空数据后重启) 时直接给出今日概览；开机自启时只在菜单栏待着，不弹窗。
            todayPanel.show()
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
