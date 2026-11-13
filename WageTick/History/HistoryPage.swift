import Observation
import SwiftUI
import WageCore

/// 历史页当前的快照，由 `HistoryPage` 刷新，视图只读。
/// 视图从它按需取月列表或某月日历：历史只在这个窗口打开时推导，不进菜单栏刷新的热路径。
@MainActor
@Observable
final class HistoryContent {
    var snapshot: Snapshot?
    /// 正在看的月份；nil 时显示月列表。
    var selectedMonth: YearMonth? {
        didSet { if selectedMonth != oldValue { selectedDay = nil } }
    }
    /// 正在看的那一天 (单日详情)；nil 时显示月日历。
    var selectedDay: LocalDate?
}

/// 历史页 (PRD F10、F11，设计稿「历史-月列表」「历史-月日历」「历史-单日详情」)：在今日概览窗口里从右边推进来，可编辑历史 (#15)。
/// 从面板底部入口、左键菜单或主菜单「历史 ⌘3」打开 (`TodayPanelWindowController.show(page:)`)。
/// 只在这一页显示时每秒刷新一次：本月结算总额含今日已赚，要跟着本月累计走 (AC-HIS-01)。
@MainActor
final class HistoryPage {
    private static let refreshInterval: TimeInterval = 1

    private let model: AppModel
    /// 编辑改了状态后通知外壳其余部分 (菜单栏) 立即重绘，如把今天改成不上班日后小牛马上晒太阳。
    private let onStateChange: () -> Void
    private let content = HistoryContent()
    private var timer: Timer?

    init(model: AppModel, onStateChange: @escaping () -> Void) {
        self.model = model
        self.onStateChange = onStateChange
    }

    /// 推进来时开始刷新。
    func appear() {
        refresh()
    }

    /// 退出去时停表，丢掉快照，下次进来回到月列表。
    func disappear() {
        timer?.invalidate()
        timer = nil
        content.snapshot = nil
        content.selectedMonth = nil
        content.selectedDay = nil
    }

    /// 页面视图；月列表的返回胶囊调 `back` 退回概览。
    func view(back: @escaping () -> Void) -> some View {
        let actions = PanelActions(
            dryRun: { [model] command in model.dryRun(command) },
            send: { [weak self] command throws(CommandError) in
                guard let self else { return }
                try model.send(command)
                // 立即刷新，编辑后所在月份与目标当场重算 (PRD 4.6.1)，不等下一次定时刷新。
                refresh()
                onStateChange()
            }
        )
        return HistoryView(content: content, actions: actions, close: back)
    }

    private func refresh() {
        content.snapshot = model.currentSnapshot()
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
