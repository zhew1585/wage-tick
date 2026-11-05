import AppKit
import WageCore

/// 组装外壳各部件：状态存储、菜单栏条目、引导窗口、今日概览面板。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: StatusItemController!
    private var onboarding: OnboardingWindowController!
    private var todayPanel: TodayPanelWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel(store: StateStore())
        todayPanel = TodayPanelWindowController(model: model) { [weak self] in
            self?.statusItem.refresh()
        }
        onboarding = OnboardingWindowController(model: model) { [weak self] in
            self?.statusItem.refresh()
        }
        statusItem = StatusItemController(
            model: model,
            openOnboarding: { [weak self] in self?.onboarding.show() },
            openTodayPanel: { [weak self] in self?.todayPanel.show() }
        )
        if !model.isOnboarded {
            onboarding.show()
        }
    }
}
