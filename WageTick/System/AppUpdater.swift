import Foundation
import Observation
import Sparkle

/// App 内更新 (ADR-0007)：Sparkle 读 GitHub Pages 上的 appcast (`SUFeedURL`)，用 EdDSA 公钥 (`SUPublicEDKey`) 校验更新包。
/// 默认只收正式版：nightly 条目带 `nightly` 渠道，Sparkle 只看允许的渠道 (`allowedChannels`)；设置里打开「接收尝鲜版」后也收 nightly。
/// 默认自动检查、静默下载；下载好后弹「新版本准备好了」(`UpdateWindowController`)，由用户选立即重启或稍后自行重启。
/// 选了稍后：下次退出时装好，菜单栏菜单里挂一项「重启以完成更新」(`pendingVersion`)。
/// 界面全部是我们自己的 (`UpdateUserDriver`)，不用 Sparkle 自带的系统样式窗口。
/// Debug 构建不启动更新器：开发版构建号是 1，任何正式版都会把它当旧版覆盖掉。
///
/// 用法：启动时创建一个并持有；设置页读 `versionText`、改 `automaticallyUpdates` 与 `receivesNightly`，
/// 主菜单与设置页调 `checkForUpdates()`，菜单栏菜单看 `pendingVersion`、点了调 `installPendingUpdate()`。
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
    /// 已下载好、等用户重启的版本，如「0.1.1」；没有时为 nil。
    private(set) var pendingVersion: String? {
        didSet { onPendingVersionChange?(pendingVersion) }
    }
    /// `pendingVersion` 变了时调用，菜单栏菜单据此加减「重启以完成更新」。
    @ObservationIgnored var onPendingVersionChange: ((String?) -> Void)?

    nonisolated private static let nightlyKey = "AppUpdater.receivesNightly"

    @ObservationIgnored private var updater: SPUUpdater?
    @ObservationIgnored private let driver: UpdateUserDriver
    /// 后台下载好的更新的「立即安装」入口，选了稍后时留着给菜单项用。
    @ObservationIgnored private var installNow: (() -> Void)?

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
        driver = UpdateUserDriver(currentVersion: version)
        super.init()
        driver.onDeferred = { [weak self] version in self?.pendingVersion = version }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        self.updater = updater
        automaticallyUpdates = updater.automaticallyDownloadsUpdates
        guard isEnabled else { return }
        do {
            try updater.start()
        } catch {
            NSLog("更新器启动失败：%@", error.localizedDescription)
        }
    }

    /// 手动检查：有新版弹「有新版本啦」，已下载好的弹「新版本准备好了」，没有新版弹「已经是最新版」。
    func checkForUpdates() {
        guard isEnabled else { return }
        updater?.checkForUpdates()
    }

    /// 菜单栏的「重启以完成更新」：后台下载好的直接安装并重启；手动下载后选了稍后的，经检查流程再弹一次确认。
    func installPendingUpdate() {
        if let installNow {
            installNow()
        } else {
            checkForUpdates()
        }
    }

    /// 打开后马上在后台查一次，有尝鲜版就按自动更新的设置下载。关掉后不会降级，等下一个正式版。
    func setReceivesNightly(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.nightlyKey)
        receivesNightly = enabled
        if enabled { updater?.checkForUpdatesInBackground() }
    }

    func setAutomaticallyUpdates(_ enabled: Bool) {
        guard let updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        updater.automaticallyDownloadsUpdates = enabled
        automaticallyUpdates = enabled
    }

    /// 后台下载好了：弹「新版本准备好了」，立即重启就装；稍后就留着，退出时 Sparkle 自己装。
    private func askToRestart(version: String, notes: [String], installNow: @escaping () -> Void) {
        self.installNow = installNow
        UpdateWindowController.shared.show(.ready(
            version: version, notes: notes,
            later: { [weak self] in self?.pendingVersion = version },
            restart: installNow
        ))
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    /// 不带渠道的条目 (正式版) 总是可见；打开「接收尝鲜版」后 nightly 渠道也可见。
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: AppUpdater.nightlyKey) ? ["nightly"] : []
    }

    /// 后台静默下载好的更新默认等 App 退出才装；这里先问用户 (返回 true 表示由我们决定何时调立即安装)。
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // Sparkle 在主线程调用代理。
        nonisolated(unsafe) let installNow = immediateInstallHandler
        MainActor.assumeIsolated {
            askToRestart(version: item.displayVersionString, notes: UpdateUserDriver.notes(of: item), installNow: installNow)
        }
        return true
    }
}
