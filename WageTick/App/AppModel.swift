import Foundation
import WageCore

/// 外壳持有的唯一状态容器："命令进、快照出"。
/// 不做任何业务计算：命令交给 `WageCore.apply`，展示数据取自 `WageCore.snapshot`。
@MainActor
final class AppModel {
    private let store: StateStore
    private var state: AppState
    /// 节假日表，由 `HolidayUpdater` 从数据源适配器取来；未就绪时为空表，只按双休。
    var holidays: HolidayTable = .empty

    init(store: StateStore) {
        self.store = store
        state = store.load()
    }

    var isOnboarded: Bool { state.profile != nil }

    /// 执行命令并立即落盘。校验失败时抛出 `CommandError`，状态不变。
    func send(_ command: Command) throws(CommandError) {
        let result = try apply(command, to: state, at: Self.now(), holidays: holidays)
        state = result.state
        store.save(state)
    }

    /// 试算：在当前状态上执行命令但不保存，返回执行后的快照。表单实时预览用它，校验失败时返回错误。
    func dryRun(_ command: Command) -> Result<Snapshot, CommandError> {
        let now = Self.now()
        do {
            return .success(snapshot(of: try apply(command, to: state, at: now, holidays: holidays).state, at: now, holidays: holidays))
        } catch {
            return .failure(error)
        }
    }

    /// 按系统当前时间与时区、当前节假日表取快照。
    func currentSnapshot() -> Snapshot {
        snapshot(of: state, at: Self.now(), holidays: holidays)
    }

    /// 时钟：系统当前时间与当前时区 (PRD 4.3.5 #11)。
    private static func now() -> Moment {
        Moment(date: Date(), timeZone: TimeZone.current)
    }
}
