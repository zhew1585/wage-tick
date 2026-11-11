import AppKit
import CoreGraphics

/// 判断某块屏幕上是不是有别的 App 正全屏 (issue #21：有 App 全屏时悬浮小牛隐藏，退出全屏恢复)。
/// 切换桌面空间、切换前台 App 时重新判断 (等全屏动画走完)，变了才回调。
///
/// 判断方法：屏幕上可见的普通层级 (layer 0) 窗口里，有别的进程的窗口正好盖满整块屏幕 (连菜单栏那条也盖住)。
/// 只读窗口的位置大小，不需要录屏权限。已知误判：开了「自动隐藏菜单栏」又把窗口拉满整屏时也会当作全屏。
@MainActor
final class FullScreenWatcher {
    /// 全屏切换动画大约 0.5 秒，动画结束后窗口才到最终大小。
    private static let settleDelay: TimeInterval = 0.7

    private let onChange: () -> Void
    private var pending: DispatchWorkItem?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(changed), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(changed), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(changed), name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    @objc private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    /// `screen` 上此刻有没有别的 App 的全屏窗口。
    static func hasFullScreenApp(on screen: NSScreen) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let target = cgRect(of: screen.frame)
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary)
            else { return false }
            return abs(bounds.minX - target.minX) < 1 && abs(bounds.minY - target.minY) < 1
                && abs(bounds.width - target.width) < 1 && abs(bounds.height - target.height) < 1
        }
    }

    /// AppKit 屏幕坐标 (原点在主屏左下) 换成 CoreGraphics 窗口坐标 (原点在主屏左上)。
    private static func cgRect(of frame: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
