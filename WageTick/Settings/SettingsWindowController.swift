import AppKit
import SwiftUI

/// 设置窗口 (PRD F12，页面 P6)，从左键菜单或主菜单「设置… ⌘,」打开。每次打开都按最新状态填好表单。外观见 `PageWindow`。
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let form: SettingsFormModel
    private lazy var window: NSWindow = makeWindow()

    init(form: SettingsFormModel) {
        self.form = form
    }

    func show() {
        if !window.isVisible {
            form.reload()
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// 录制快捷键中途关窗或切走：结束录制，恢复全局快捷键，别的窗口的按键不再被吞掉。
    func windowWillClose(_ notification: Notification) {
        form.endRecordingHotkey()
    }

    func windowDidResignKey(_ notification: Notification) {
        form.endRecordingHotkey()
    }

    /// 从系统设置改完通知权限切回来时，提示随之更新。
    func windowDidBecomeKey(_ notification: Notification) {
        form.refreshNotificationPermission()
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(form: form, close: { [weak self] in self?.window.close() })
        return PageWindow.make(title: "设置", rootView: view, delegate: self)
    }
}
