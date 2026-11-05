import OSLog
import ServiceManagement

/// 开机自启：用系统登录项机制 (SMAppService) 注册或注销本 App。
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: AppIdentity.bundleID, category: "LaunchAtLogin")

    /// 让登录项与牛马的选择一致。失败只记日志，不影响其他功能。
    static func set(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            logger.error("开机自启设置失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
