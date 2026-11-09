import AppKit
import Sparkle

/// 把 Sparkle 的各个阶段画成我们自己的更新窗口 (`UpdateWindowController`)，替换 Sparkle 自带的系统样式窗口 (ADR-0007)。
/// 只管界面：要不要下载、何时安装仍由 Sparkle 决定，这里把用户的选择交还给它。
/// 后台静默下载完的那次提醒不走这里，见 `AppUpdater` 的 `willInstallUpdateOnQuit`。
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {
    /// 用户在「已准备好」选了稍后：交给 `AppUpdater` 在菜单栏菜单里挂「重启以完成更新」。
    var onDeferred: ((String) -> Void)?

    private let window = UpdateWindowController.shared
    private let currentVersion: String
    private var version = ""
    private var received: UInt64 = 0
    private var expected: UInt64 = 0
    private var cancelDownload: () -> Void = {}

    init(currentVersion: String) {
        self.currentVersion = currentVersion
    }

    /// 更新内容：appcast 条目的纯文本说明，一行一条 (CI 按提交标题生成，见 scripts/ci/release-notes.sh)。
    static func notes(of item: SUAppcastItem) -> [String] {
        (item.itemDescription ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
    }

    // MARK: 检查

    /// Info.plist 已开启自动检查，不会问；万一问了，按开启自动检查回答。
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    /// 手动检查通常一两秒就有结果，不弹「检查中」。
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        version = appcastItem.displayVersionString
        let notes = Self.notes(of: appcastItem)
        if state.stage == .notDownloaded {
            window.show(.found(
                version: version, current: currentVersion, notes: notes,
                later: { reply(.dismiss) }, download: { reply(.install) }
            ))
        } else {
            // 已经下载好 (自动下载过，或上次选了稍后)：直接问要不要重启。
            showReady(notes: notes) { reply($0) }
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        window.show(.upToDate(current: currentVersion, ok: acknowledgement))
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        window.show(.failed(message: error.localizedDescription, ok: acknowledgement))
    }

    // MARK: 下载

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        received = 0
        expected = 0
        cancelDownload = cancellation
        window.show(downloading)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expected = expectedContentLength
        window.update(downloading)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        window.update(downloading)
    }

    func showDownloadDidStartExtractingUpdate() {
        window.update(.extracting(version: version))
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    private var downloading: UpdateScreen {
        .downloading(version: version, received: received, expected: expected, cancel: cancelDownload)
    }

    // MARK: 安装

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        showReady(notes: []) { reply($0) }
    }

    /// ③ 已准备好：立即重启交给 Sparkle 安装并重启；稍后则保留下载好的更新，菜单栏菜单里挂一项。
    private func showReady(notes: [String], reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let version = version
        window.show(.ready(
            version: version, notes: notes,
            later: { [weak self] in
                reply(.dismiss)
                self?.onDeferred?(version)
            },
            restart: { reply(.install) }
        ))
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        window.close()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        window.close()
    }

    func showUpdateInFocus() {
        guard window.isShowing else { return }
        NSApp.activate()
    }
}
