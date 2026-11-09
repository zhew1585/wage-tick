import Foundation
import Observation
import Sparkle

/// App 内更新 (ADR-0007)：Sparkle 读 GitHub Pages 上的 appcast (`SUFeedURL`)，用 EdDSA 公钥 (`SUPublicEDKey`) 校验更新包。
/// 默认只收正式版：nightly 条目带 `nightly` 渠道，Sparkle 只看允许的渠道 (`allowedChannels`)；设置里打开「接收尝鲜版」后也收 nightly。
/// 默认自动检查、静默下载；下载好后立即安装并重启 App，不等退出 (菜单栏常驻的 App 很少退出)。
/// Debug 构建不启动更新器：开发版构建号是 1，任何正式版都会把它当旧版覆盖掉。
///
/// 用法：启动时创建一个并持有；设置页读 `versionText`、改 `automaticallyUpdates` 与 `receivesNightly`，主菜单与设置页调 `checkForUpdates()`。
@MainActor
@Observable
final class AppUpdater: NSObject {
    /// 更新器是否在跑 (Release 构建)。
    let isEnabled: Bool
    /// 当前版本，如「0.1.1 (42)」：版本号与 CI 的构建号。
    let versionText: String
    /// 自动检查并安装更新；关掉后只在点「检查更新」时检查。
    private(set) var automaticallyUpdates = true
    /// 接收尝鲜版 (nightly)：记在 UserDefaults，Sparkle 每次检查时经 `allowedChannels` 读取。
    private(set) var receivesNightly = UserDefaults.standard.bool(forKey: AppUpdater.nightlyKey)

    nonisolated private static let nightlyKey = "AppUpdater.receivesNightly"

    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    override init() {
        #if DEBUG
        isEnabled = false
        #else
        isEnabled = true
        #endif
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        versionText = "\(version) (\(build))"
        super.init()
        let controller = SPUStandardUpdaterController(startingUpdater: isEnabled, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        automaticallyUpdates = controller.updater.automaticallyDownloadsUpdates
    }

    /// 手动检查：有新版时弹 Sparkle 自带的窗口，可以看说明、安装并重启。
    func checkForUpdates() {
        guard isEnabled else { return }
        controller?.checkForUpdates(nil)
    }

    /// 打开后马上在后台查一次，有尝鲜版就按自动更新的设置下载安装。关掉后不会降级，等下一个正式版。
    func setReceivesNightly(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.nightlyKey)
        receivesNightly = enabled
        if enabled { controller?.updater.checkForUpdatesInBackground() }
    }

    func setAutomaticallyUpdates(_ enabled: Bool) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        updater.automaticallyDownloadsUpdates = enabled
        automaticallyUpdates = enabled
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    /// 不带渠道的条目 (正式版) 总是可见；打开「接收尝鲜版」后 nightly 渠道也可见。
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: AppUpdater.nightlyKey) ? ["nightly"] : []
    }

    /// 静默下载好的更新本来要等 App 退出才装；这里立即安装，Sparkle 装完会重新打开 App。
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        immediateInstallHandler()
        return true
    }
}
