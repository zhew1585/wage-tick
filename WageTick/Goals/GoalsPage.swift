import Observation
import SwiftUI
import WageCore

/// 目标页当前要展示的内容，由 `GoalsPage` 按快照刷新，视图只读。
@MainActor
@Observable
final class GoalsContent {
    var list = GoalList.empty
    /// 队列为空时的提示，如「给自己定个目标吧」。
    var emptyText: String?

    /// 按快照填好各项。
    func update(from snap: Snapshot) {
        list = snap.goals ?? .empty
        if case .empty(let text) = snap.panel?.goal {
            emptyText = text
        } else {
            emptyText = nil
        }
    }
}

/// 目标页 (PRD F8，页面 P3)：在今日概览窗口里从右边推进来，从面板底部入口、面板的目标卡 (累计中的卡片或空目标区)、左键菜单或主菜单「目标 ⌘2」打开。
/// 只在这一页显示时每秒刷新一次，让累计中目标的累计额跟着走。页头的返回退回概览。
@MainActor
final class GoalsPage {
    private static let refreshInterval: TimeInterval = 1

    private let model: AppModel
    private let content = GoalsContent()
    private var timer: Timer?
    /// 这一页正显示着 (推进来到退出去之间)；只有这时才排下一次定时刷新。
    private var isActive = false

    init(model: AppModel) {
        self.model = model
    }

    func appear() {
        isActive = true
        refresh()
    }

    func disappear() {
        isActive = false
        timer?.invalidate()
        timer = nil
    }

    func view(back: @escaping () -> Void) -> some View {
        GoalsView(
            content: content,
            send: { [weak self] (command: Command) throws(CommandError) in try self?.send(command) },
            close: back
        )
    }

    /// 执行目标命令 (新建、编辑、删除、排序)，成功后立即刷新列表。校验失败时抛出 `CommandError`，由视图展示提示。
    private func send(_ command: Command) throws(CommandError) {
        try model.send(command)
        refresh()
    }

    /// 取最新快照；页面显示着时排下一次。退出去之后 (滑出动画里松手的拖动排序等) 只刷新内容，不再把停掉的定时器拉起来。
    private func refresh() {
        content.update(from: model.currentSnapshot())
        timer?.invalidate()
        timer = nil
        guard isActive else { return }
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
