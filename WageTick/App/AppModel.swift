import Foundation
import WageCore

/// 外壳持有的唯一状态容器："命令进、快照出"。
/// 不做任何业务计算：命令交给 `WageCore.apply`，展示数据取自 `WageCore.snapshot`。
@MainActor
final class AppModel {
    private let store: StateStore
    private var state: AppState

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

    /// 先发「推进到此刻」处理随时间发生的变化 (白干到 23:59:59 自动停止)，再按同一此刻取快照。
    /// 每次刷新都会调用，只在状态真的变了才落盘。
    func currentSnapshot() -> Snapshot {
        let now = Self.now()
        advance(at: now)
        return snapshot(of: state, at: now)
    }

    private func advance(at now: Moment) {
        do {
            let next = try apply(.advance, to: state, at: now).state
            guard next != state else { return }
            state = next
            store.save(state)
        } catch {
            // 推进到此刻没有校验，不会被拒绝。
            assertionFailure("推进到此刻失败：\(error.message)")
        }
    }

    /// 时钟：系统当前时间与当前时区 (PRD 4.3.5 #11)。
    private static func now() -> Moment {
        Moment(date: Date(), timeZone: TimeZone.current)
    }
}
