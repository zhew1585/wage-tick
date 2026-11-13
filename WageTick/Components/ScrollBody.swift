import AppKit
import SwiftUI

/// 固定尺寸窗口 (`WindowMetrics`) 里夹在页头与底部按钮栏之间的内容区：占满剩余高度，放不下时滚动，元素保持原尺寸；
/// 放得下时内容靠上、不回弹。放进按内容定大小的 sheet 里时，高度就是内容高度。
/// 不显示滚动条 (Allen 定：能滑就行)，触控板、滚轮照常滑动。
///
/// 用法：`VStack(spacing: 0) { 头图; ScrollBody { 内容 }; 底部按钮栏 }`
struct ScrollBody<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .background(HiddenScrollers())
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// 找到所在的 `NSScrollView`，把滚动条整个去掉 (不占宽度、也不会在内容放得下时露出来)；滑动不受影响。
/// `scrollIndicators(.hidden)` 在 macOS 上接了鼠标时仍可能留一条常驻滚动条，这里在 AppKit 一层再关一次；
/// 系统偏好变了 (插拔鼠标) 时 AppKit 可能把滚动条装回来，再关一次。
struct HiddenScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> HiddenScrollersView { HiddenScrollersView() }
    func updateNSView(_ view: HiddenScrollersView, context: Context) {}
}

final class HiddenScrollersView: NSView {
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
        hideScrollers()
    }

    /// AppKit 收到同一条通知后才改回系统样式，排到下一轮再关。
    @objc private func preferredStyleChanged() {
        DispatchQueue.main.async { [weak self] in self?.hideScrollers() }
    }

    private func hideScrollers() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
    }
}
