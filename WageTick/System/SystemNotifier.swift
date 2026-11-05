import AppKit
import OSLog
import UserNotifications
import WageCore

/// 系统通知 (PRD F13)：把核心给出的领域事件原样发成系统通知，文案全部来自核心。
/// 首次需要发通知时才请求权限 (PRD 6.3)；被拒时不发，设置页提示 (PRD 4.3.5 #15)。点通知打开今日概览面板。
@MainActor
final class SystemNotifier: NSObject {
    private let openPanel: () -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "Notifier")
    /// 系统设置里的通知页。
    private static let notificationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    /// 需在 App 启动完成前创建，系统才能把"点了通知启动 App"交给代理。
    init(openPanel: @escaping () -> Void) {
        self.openPanel = openPanel
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// 每个事件发一条通知。
    func post(_ events: [DomainEvent]) {
        for event in events {
            switch event {
            case .offWork(let message), .goalReached(let message): post(message: message)
            }
        }
    }

    /// 系统是否拒绝了通知权限，设置页据此显示提示。还没问过时不算拒绝。
    func isDenied() async -> Bool {
        await authorizationStatus() == .denied
    }

    /// 打开系统设置的通知页，让牛马自己把权限打开。
    func openSystemSettings() {
        NSWorkspace.shared.open(Self.notificationSettingsURL)
    }

    private func post(message: String) {
        Task {
            guard await isAuthorized() else { return }
            let content = UNMutableNotificationContent()
            content.body = message
            content.sound = .default
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            } catch {
                logger.error("系统通知发送失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 只取出权限状态：`UNNotificationSettings` 不是 Sendable，不能整个跨出回调。
    private func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { continuation.resume(returning: $0.authorizationStatus) }
        }
    }

    /// 已授权直接放行；还没问过就在这时请求 (首次需要时)；被拒不再打扰。
    private func isAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                logger.error("请求通知权限失败：\(error.localizedDescription, privacy: .public)")
                return false
            }
        default:
            return false
        }
    }
}

extension SystemNotifier: UNUserNotificationCenterDelegate {
    /// 菜单栏 App 常被系统视为前台，不处理时通知不会弹出。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// 点通知打开今日概览面板 (F13)。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await openPanelFromNotification()
    }

    /// 代理回调不在主线程，经这个 MainActor 方法跳回主线程再开面板。
    private func openPanelFromNotification() {
        openPanel()
    }
}
