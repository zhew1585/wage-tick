import Observation
import SwiftUI
import WageCore

/// 目标页当前要展示的内容，由窗口控制器按快照刷新；`route` 是窗口里正在显示的页面，视图切页时改它。
@MainActor
@Observable
final class GoalsContent {
    var list = GoalList.empty
    var route = GoalsRoute.queue {
        didSet { if case .form = route { formSession += 1 } }
    }
    /// 每次打开目标表单加 1，表单按它换一个新视图，上一次没保存或刚保存过的输入不会留下来。
    private(set) var formSession = 0

    /// 按快照填好各项。
    func update(from snap: Snapshot) {
        list = snap.goals ?? .empty
    }
}

/// 目标页里的子页面：攒钱队列 (首页)、已到手、新建或编辑目标的表单；后两个从右边推进来。
enum GoalsRoute: Equatable {
    case queue
    case earned
    case form(GoalFormView.Mode)
}

/// 目标页 (PRD F8，页面 P3)：在今日概览窗口里从右边推进来，从面板底部入口、目标卡、左键菜单或主菜单「目标 ⌘2」打开。
/// 只在这一页显示时每秒刷新一次，让累计中目标的累计额跟着走。每次进来回到攒钱队列；头图上的「返回」退回概览。
@MainActor
final class GoalsPage {
    private static let refreshInterval: TimeInterval = 1

    private let model: AppModel
    private let content = GoalsContent()
    private var timer: Timer?

    init(model: AppModel) {
        self.model = model
    }

    func appear() {
        content.route = .queue
        refresh()
    }

    func disappear() {
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

    private func refresh() {
        content.update(from: model.currentSnapshot())
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
