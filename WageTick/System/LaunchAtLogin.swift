import OSLog
import ServiceManagement

/// 开机自启：用系统登录项机制 (SMAppService) 注册或注销本 App。
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: AppIdentity.bundleID, category: "LaunchAtLogin")

    /// 让登录项与牛马的选择一致，返回是否成功。失败只记日志，不影响其他功能。
    /// 系统要求牛马在登录项里手动批准 (`.requiresApproval`) 时还没生效，也算失败。
    @discardableResult
    static func set(enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
            return (service.status == .enabled) == enabled
        } catch {
            logger.error("开机自启设置失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
