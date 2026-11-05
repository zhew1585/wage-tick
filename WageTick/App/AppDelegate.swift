import AppKit
import WageCore

/// 组装外壳各部件：状态存储、菜单栏条目、引导窗口、今日概览面板、设置窗口、目标管理、历史窗口、系统通知。
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel(store: StateStore())
        // 菜单栏第一次刷新就会推进到此刻，事件出口要先接好。
        notifier = SystemNotifier { [weak self] in self?.todayPanel.show() }
        model.onEvents = { [weak self] events in self?.notifier.post(events) }
        // 先交出内置与缓存的节假日数据，菜单栏第一次刷新就按它计算。
        holidayUpdater = HolidayUpdater(model: model)
        holidayUpdater.start()
        goals = GoalsWindowController(model: model)
        todayPanel = TodayPanelWindowController(model: model, openGoals: { [weak self] in self?.goals.show() }) { [weak self] in
            self?.statusItem.refresh()
        }
        onboarding = OnboardingWindowController(model: model) { [weak self] in
            self?.statusItem.refresh()
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
        if !model.isOnboarded {
            onboarding.show()
        }
    }
}
