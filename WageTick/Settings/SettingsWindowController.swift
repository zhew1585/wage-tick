import AppKit
import SwiftUI

/// 设置窗口 (PRD F12，页面 P6)，从左键菜单或主菜单「设置… ⌘,」打开。每次打开都按最新状态填好表单。外观见 `PageWindow`，头图上的「返回」即关窗。
/// 只在窗口可见时每秒刷新一次显示模式预览，让金额、进度跟着走。
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let refreshInterval: TimeInterval = 1

    private let form: SettingsFormModel
    private let updater: AppUpdater
    private lazy var window: NSWindow = makeWindow()
    private lazy var placement = WindowPlacement(window: window, name: "Settings")
    private var timer: Timer?

    init(form: SettingsFormModel, updater: AppUpdater) {
        self.form = form
        self.updater = updater
    }

    func show() {
        if !window.isVisible && !window.isMiniaturized {
            form.reload()
            placement.place()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        scheduleRefresh()
    }

    /// 关窗后停掉显示模式预览的定时刷新。
    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.form.refreshMenuBarPreviews() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 从系统设置改完通知权限切回来时，提示随之更新。
    func windowDidBecomeKey(_ notification: Notification) {
        form.refreshNotificationPermission()
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(form: form, updater: updater) { [weak self] in self?.window.close() }
        return PageWindow.make(title: "设置", rootView: view, delegate: self)
    }
}
