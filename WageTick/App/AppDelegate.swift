import AppKit
import WageCore

/// 组装外壳各部件：状态存储、菜单栏条目、引导窗口。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusItem: StatusItemController!
    private var onboarding: OnboardingWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel(store: StateStore())
        onboarding = OnboardingWindowController(model: model) { [weak self] in
            self?.statusItem.refresh()
        }
        statusItem = StatusItemController(model: model) { [weak self] in
            self?.onboarding.show()
        }
        if !model.isOnboarded {
            onboarding.show()
        }
    }
}
