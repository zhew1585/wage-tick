import AppKit
import SwiftUI

/// 设置窗口 (PRD F12，页面 P6)，从左键菜单「设置… ⌘,」打开。每次打开都按最新状态填好表单。
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

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(form: form)))
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
