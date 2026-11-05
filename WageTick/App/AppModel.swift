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

    /// 试算：在状态副本上执行命令后取快照，不改状态、不落盘。
    /// 表单的实时汇总用它，数字全部来自核心 (如请假表单的当日计划、今日上限)。
    func preview(_ command: Command) -> Result<Snapshot, CommandError> {
        let now = Self.now()
        do throws(CommandError) {
            return .success(snapshot(of: try apply(command, to: state, at: now).state, at: now))
        } catch {
            return .failure(error)
        }
    }

    /// 按系统当前时间与时区取快照。
    func currentSnapshot() -> Snapshot {
        snapshot(of: state, at: Self.now())
    }

    /// 时钟：系统当前时间与当前时区 (PRD 4.3.5 #11)。
    private static func now() -> Moment {
        Moment(date: Date(), timeZone: TimeZone.current)
    }
}
