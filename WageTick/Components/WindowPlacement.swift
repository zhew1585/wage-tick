import AppKit

/// 窗口打开时放在哪，所有窗口共用：
/// - 没被牛马拖过：放在鼠标所在屏幕可用区域的正中。
/// - 拖过：回到上次拖到的位置 (存在 UserDefaults，跨启动)；那个位置已不在任何屏幕上 (拔了外接屏) 时退回居中。
/// - 接替另一个窗口 (引导完成后的今日概览)：`place(replacing:)` 对齐它的左边和顶边，不记。
///
/// 用法：窗口控制器持有 `WindowPlacement(window: window, name: "Goals")`，窗口没开着时、显示前调 `place()`。
@MainActor
final class WindowPlacement: NSObject {
    private let window: NSWindow
    private let defaultsKey: String
    /// 上次摆好位置之后牛马拖过窗口。`windowWillMove` 只在牛马拖动时发，程序里摆位置不发。
    private var draggedByUser = false

    init(window: NSWindow, name: String) {
        self.window = window
        defaultsKey = "WindowOrigin.\(name)"
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(willMove), name: NSWindow.willMoveNotification, object: window)
        center.addObserver(self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: window)
    }

    /// 放到上次拖到的位置，没拖过就居中。
    func place() {
        draggedByUser = false
        if let origin = savedOrigin, isOnScreen(NSRect(origin: origin, size: window.frame.size)) {
            window.setFrameOrigin(origin)
        } else {
            center()
        }
    }

    /// 接替另一个窗口：左边和顶边对齐 `frame` (所有窗口同尺寸，即同一位置)。
    func place(replacing frame: NSRect) {
        draggedByUser = false
        window.setFrameTopLeftPoint(NSPoint(x: frame.minX, y: frame.maxY))
    }

    private func center() {
        let size = window.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        window.setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded()))
    }

    /// 标题栏那一条落在某块屏幕的可用区域里，牛马才拖得回来。
    private func isOnScreen(_ frame: NSRect) -> Bool {
        let titlebar = NSRect(x: frame.minX, y: frame.maxY - WindowChrome.Titlebar.standard.height, width: frame.width, height: WindowChrome.Titlebar.standard.height)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(titlebar) }
    }

    private var savedOrigin: NSPoint? {
        UserDefaults.standard.string(forKey: defaultsKey).map(NSPointFromString)
    }

    @objc private func willMove(_ notification: Notification) {
        draggedByUser = true
    }

    @objc private func didMove(_ notification: Notification) {
        guard draggedByUser else { return }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: defaultsKey)
    }
}
