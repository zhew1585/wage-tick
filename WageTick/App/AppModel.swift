import Foundation
import OSLog
import WageCore

/// 外壳持有的唯一状态容器："命令进、快照出"。
/// 不做任何业务计算：命令交给 `WageCore.apply`，展示数据取自 `WageCore.snapshot`。
@MainActor
final class AppModel {
    private let store: StateStore
    private var state: AppState
    /// 节假日表，由 `HolidayUpdater` 从数据源适配器取来；未就绪时为空表，只按双休。
    var holidays: HolidayTable = .empty
    /// 「推进到此刻」产生的领域事件 (下班、目标达成) 交给它发系统通知。
    var onEvents: (([DomainEvent]) -> Void)?
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "AppModel")
    /// 清空数据后到退出前不再落盘，免得刷新把旧状态写回去。
    private var isResetting = false

    init(store: StateStore) {
        self.store = store
        state = store.load()
    }

    var isOnboarded: Bool { state.profile != nil }

    /// 执行命令并立即落盘。校验失败时抛出 `CommandError`，状态不变。
    func send(_ command: Command) throws(CommandError) {
        let result = try apply(command, to: state, at: Self.now(), holidays: holidays)
        state = result.state
        save()
        deliver(result.events)
    }

    /// 清空全部数据 (设置页「清空数据并重启」)：状态文件挪成备份，之后不再落盘，调用方随即重启 App。
    func resetAllData() {
        isResetting = true
        store.reset()
    }

    private func save() {
        guard !isResetting else { return }
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

    /// 先发「推进到此刻」处理随时间发生的变化 (白干到 23:59:59 自动停止、累计中目标达成、跨过计划下班)，
    /// 再按同一此刻、当前节假日表取快照。每次刷新都走这里。
    func currentSnapshot() -> Snapshot {
        let now = Self.now()
        advance(at: now)
        return snapshot(of: state, at: now, holidays: holidays)
    }

    /// 刷新很频繁，只在状态真的变了才落盘；先落盘再交出事件，重启后不会重复发。
    private func advance(at now: Moment) {
        do {
            let result = try apply(.advance, to: state, at: now, holidays: holidays)
            if result.state != state {
                state = result.state
                save()
            }
            deliver(result.events)
        } catch {
            // 推进到此刻没有校验，正常不会被拒绝；万一被拒，状态不变，下次刷新再推进。
            logger.error("推进到此刻失败：\(error.message, privacy: .public)")
        }
    }

    /// 领域事件只从这里交出去，任何命令产生的都一样处理。
    private func deliver(_ events: [DomainEvent]) {
        if !events.isEmpty { onEvents?(events) }
    }

    /// 时钟：系统当前时间与当前时区 (PRD 4.3.5 #11)。
    private static func now() -> Moment {
        Moment(date: Date(), timeZone: TimeZone.current)
    }
}
