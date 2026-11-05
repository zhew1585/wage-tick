import Foundation
import OSLog
import WageCore

/// 外壳持有的唯一状态容器："命令进、快照出"。
/// 不做任何业务计算：命令交给 `WageCore.apply`，展示数据取自 `WageCore.snapshot`。
@MainActor
final class AppModel {
    private let store: StateStore
    private var state: AppState
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "AppModel")

    init(store: StateStore) {
        self.store = store
        state = store.load()
    }

    var isOnboarded: Bool { state.profile != nil }

    /// 执行命令并立即落盘。校验失败时抛出 `CommandError`，状态不变。
    func send(_ command: Command) throws(CommandError) {
        let result = try apply(command, to: state, at: Self.now())
        state = result.state
        store.save(state)
    }

    /// 先推进到此刻 (如累计中目标达成)，再按系统当前时间与时区取快照。每次刷新都走这里。
    func currentSnapshot() -> Snapshot {
        let now = Self.now()
        advance(at: now)
        return snapshot(of: state, at: now)
    }

    /// 发「推进到此刻」命令。刷新很频繁，只在状态真的变化时落盘。
    /// 领域事件 (目标达成通知) 留给 #13。
    private func advance(at now: Moment) {
        do {
            let result = try apply(.advance, to: state, at: now)
            guard result.state != state else { return }
            state = result.state
            store.save(state)
        } catch {
            logger.error("推进到此刻失败：\(error.message, privacy: .public)")
        }
    }

    /// 时钟：系统当前时间与当前时区 (PRD 4.3.5 #11)。
    private static func now() -> Moment {
        Moment(date: Date(), timeZone: TimeZone.current)
    }
}
