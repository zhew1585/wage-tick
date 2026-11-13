import AppKit
import SwiftUI

/// 首次引导窗口。中途关闭后再点菜单栏小牛会回到同一个窗口，已填内容保留 (AC-ONB-04)。
@MainActor
final class OnboardingWindowController {
    private let model: AppModel
    private let onComplete: (NSRect) -> Void
    private lazy var window: NSWindow = makeWindow()
    private lazy var placement = WindowPlacement(window: window, name: "Onboarding")

    /// `onComplete`：引导完成时回调，参数是引导窗口的 frame，用来刷新菜单栏并在原位打开今日概览；回调之后引导窗口关闭。
    init(model: AppModel, onComplete: @escaping (NSRect) -> Void) {
        self.model = model
        self.onComplete = onComplete
    }

    func show() {
        NSApp.activate()
        if !window.isVisible && !window.isMiniaturized { placement.place() }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = OnboardingView(model: model) { [weak self] in
            guard let self else { return }
            // 先在原位打开今日概览再关引导，中间不闪空。
            onComplete(window.frame)
            window.close()
        }
        // 设计稿是一整张卡片：标题栏透明、内容铺满，红绿灯齐全 (中途关闭见 AC-ONB-04)，步骤条在标题栏下面。
        return WindowChrome.makeWindow(title: "牛马鼓励器", titlebar: .hero, rootView: view)
    }
}
