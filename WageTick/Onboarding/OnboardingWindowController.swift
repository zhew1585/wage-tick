import AppKit
import SwiftUI

/// 首次引导窗口。中途关闭后再点菜单栏小牛会回到同一个窗口，已填内容保留 (AC-ONB-04)。
@MainActor
final class OnboardingWindowController {
    private let model: AppModel
    private let onComplete: () -> Void
    private lazy var window: NSWindow = makeWindow()

    /// `onComplete`：引导完成、窗口关闭后回调，用来刷新菜单栏并打开今日概览。
    init(model: AppModel, onComplete: @escaping () -> Void) {
        self.model = model
        self.onComplete = onComplete
    }

    func show() {
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(model: model) { [weak self] in
            self?.window.close()
            self?.onComplete()
        }
        let controller = NSHostingController(rootView: view)
        // 不让出标题栏的安全区，窗口正好是设计稿的 360×560，否则底部会多出一条标题栏高的空白。
        controller.safeAreaRegions = []
        let window = NSWindow(contentViewController: controller)
        // 设计稿是一整张卡片：标题栏透明、内容铺满，红绿灯齐全 (中途关闭见 AC-ONB-04)，步骤条排在红绿灯右边。
        WindowChrome.apply(to: window, title: "牛马鼓励器", titlebar: .standard)
        window.setContentSize(OnboardingView.size)
        return window
    }
}
