import AppKit
import SwiftUI

/// 首次引导窗口。中途关闭后再点菜单栏小牛会回到同一个窗口，已填内容保留 (AC-ONB-04)。
@MainActor
final class OnboardingWindowController {
    /// 引导完成后回调，用来刷新菜单栏。
    var onComplete: () -> Void = {}

    private let model: AppModel
    private lazy var window: NSWindow = makeWindow()

    init(model: AppModel) {
        self.model = model
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
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "牛马鼓励器"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }
}
