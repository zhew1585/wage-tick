import AppKit
import SwiftUI

/// 固定尺寸窗口 (`WindowMetrics`) 里夹在页头与底部按钮栏之间的内容区：占满剩余高度，放不下时滚动，元素保持原尺寸；
/// 放得下时内容靠上、不回弹。放进按内容定大小的 sheet 里时，高度就是内容高度。
/// 滚动条固定用悬浮样式 (滚动时才出现、不占宽度)：接了鼠标时系统默认的常驻滚动条会占掉约 15pt，把 360 宽的内容挤窄。
///
/// 用法：`VStack(spacing: 0) { PageHeader(...); ScrollBody { 内容 }; 底部按钮栏 }`
struct ScrollBody<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .background(OverlayScrollers())
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// 找到所在的 `NSScrollView`，把滚动条样式定为悬浮；系统偏好变了 (插拔鼠标) 时 AppKit 会改回去，再定一次。
private struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollersView { OverlayScrollersView() }
    func updateNSView(_ view: OverlayScrollersView, context: Context) {}
}

private final class OverlayScrollersView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferredStyleChanged),
            name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyOverlayStyle()
    }

    /// AppKit 收到同一条通知后才改回系统样式，排到下一轮再定。
    @objc private func preferredStyleChanged() {
        DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
    }

    private func applyOverlayStyle() {
        guard let scrollView = enclosingScrollView, scrollView.scrollerStyle != .overlay else { return }
        scrollView.scrollerStyle = .overlay
    }
}
