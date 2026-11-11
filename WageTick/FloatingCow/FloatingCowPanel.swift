import AppKit
import SwiftUI

/// 悬浮小牛的窗口：无边框、透明、不抢焦点的浮动面板 (issue #21)。
/// 浮在普通窗口之上，出现在所有桌面空间里；不带 `.fullScreenAuxiliary`，别的 App 全屏的空间里不出现
/// (再由 `FullScreenWatcher` 兜底收起)。永远不成为 key window：点它不会把焦点从正在打字的 App 抢走。
/// 透明的地方 (小牛四周留白) 点击会穿透到下面的窗口。
final class FloatingCowPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: FloatingCowMetrics.canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // 投影由 SwiftUI 画在气泡、小条上；窗口本身的投影会沿着透明留白画出一个框。
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 浮窗的内容视图：SwiftUI 画面上面盖一层接住全部鼠标事件，区分单击、拖动与右键，交给控制器处理。
/// 拖动自己挪窗口 (不用 `performDrag`)，好在松手时判断贴边、在没拖动时当作单击。
final class FloatingCowEventView: NSView {
    /// 按下后移动不到这么远松手算单击。
    private static let clickTolerance: CGFloat = 3

    var onClick: () -> Void = {}
    /// 开始拖动：控制器可以在这里换成展开的样子，返回此刻浮窗的左下角作为拖动起点。
    var onDragStart: () -> NSPoint = { .zero }
    var onDragEnd: () -> Void = {}
    var onRightClick: (NSEvent, NSView) -> Void = { _, _ in }

    private var mouseDownLocation: NSPoint?
    private var dragOrigin: NSPoint?

    init<Content: View>(rootView: Content) {
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不从 nib 加载") }

    /// 所有点击都由这一层处理，SwiftUI 画面只负责画。
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    /// 浮窗不是 key window，第一下点击也要算数。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        dragOrigin = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, let window else { return }
        let mouse = NSEvent.mouseLocation
        if dragOrigin == nil {
            guard hypot(mouse.x - start.x, mouse.y - start.y) >= Self.clickTolerance else { return }
            let origin = onDragStart()
            // 开始拖动时浮窗可能刚换了大小 (收起换成展开)，以此刻为起点，鼠标与小牛的相对位置不跳。
            dragOrigin = origin
            mouseDownLocation = mouse
            return
        }
        guard let origin = dragOrigin, let start = mouseDownLocation else { return }
        window.setFrameOrigin(NSPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownLocation = nil
            dragOrigin = nil
        }
        guard mouseDownLocation != nil else { return }
        if dragOrigin == nil {
            onClick()
        } else {
            onDragEnd()
        }
    }

    var isDragging: Bool { dragOrigin != nil }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick(event, self)
    }
}
