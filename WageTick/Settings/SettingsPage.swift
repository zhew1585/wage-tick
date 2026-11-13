import SwiftUI

/// 设置页 (PRD F12，页面 P6)：在今日概览窗口里从右边推进来，从面板底部入口、左键菜单、主菜单「设置… ⌘,」或悬浮小牛右键打开。
/// 每次进来都按最新状态填好表单；头图上的「返回」退回概览。只在这一页显示时每秒刷新一次显示模式预览，让金额、进度跟着走。
@MainActor
final class SettingsPage {
    private static let refreshInterval: TimeInterval = 1

    private let form: SettingsFormModel
    private let updater: AppUpdater
    private var timer: Timer?

    init(form: SettingsFormModel, updater: AppUpdater) {
        self.form = form
        self.updater = updater
    }

    func appear() {
        form.reload()
        form.refreshNotificationPermission()
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.form.refreshMenuBarPreviews() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func disappear() {
        timer?.invalidate()
        timer = nil
    }

    /// 从系统设置改完通知权限切回窗口时，提示随之更新。
    func windowBecameKey() {
        form.refreshNotificationPermission()
    }

    func view(back: @escaping () -> Void) -> some View {
        SettingsView(form: form, updater: updater, close: back)
    }
}
