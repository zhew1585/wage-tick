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
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "牛马鼓励器"
        // 设计稿是一整张卡片，没有标题栏：标题栏透明、内容铺满，只留关闭按钮 (中途关闭见 AC-ONB-04)。
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Palette.bg)
        window.setContentSize(OnboardingView.size)
        window.isReleasedWhenClosed = false
        return window
    }
}
