import AppKit
import HolidaySource
import WageCore

/// 把节假日数据源适配器接到外壳：启动时立刻交出内置与缓存数据，再在后台补齐今年的数据。
/// 今年数据缺失时每小时、以及唤醒或改系统时间后再试一次 (PRD 4.3.5 #10)；已有数据时 `ensure` 不联网。
/// 拿到新数据后写进 `AppModel.holidays`，菜单栏与面板下一次刷新即按新表重算 (#16)。
@MainActor
final class HolidayUpdater {
    /// 重试间隔。数据已有时这只是一次本地判断，不会联网。
    private static let retryInterval: TimeInterval = 60 * 60

    private let model: AppModel
    private let source: HolidaySource
    private var timer: Timer?

    init(model: AppModel) {
        self.model = model
        source = HolidaySource(
            bundledDirectory: Bundle.main.resourceURL,
            cacheDirectory: Self.cacheDirectory,
            fetcher: HolidayCNFetcher()
        )
        model.holidays = source.table
    }

    /// 立即尝试一次，并开始定时重试与监听唤醒、改时间。
    func start() {
        update()
        let timer = Timer(timeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clockChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: .NSSystemClockDidChange, object: nil)
    }

    /// 确保系统当前年份有数据 (跨年后自然换成新一年)，完成后交给模型。
    private func update() {
        let year = Calendar.current.component(.year, from: Date())
        Task {
            await source.ensure(year: year)
            model.holidays = source.table
        }
    }

    @objc private func clockChanged() {
        update()
    }

    /// ~/Library/Application Support/<bundle id>/holidays，与状态文件同一目录下。
    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: AppIdentity.bundleID).appending(path: "holidays")
    }
}
