import Observation
import SwiftUI
import WageCore

/// 历史页当前的快照，由 `HistoryPage` 刷新，视图只读。
/// 视图从它按需取月列表或某月日历：历史只在这一页显示时推导，不进菜单栏刷新的热路径。
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
    /// 这一页正显示着 (推进来到退出去之间)；只有这时才排下一次定时刷新。
    private var isActive = false

    init(model: AppModel, onStateChange: @escaping () -> Void) {
        self.model = model
        self.onStateChange = onStateChange
    }

    /// 推进来时回到月列表并开始刷新。
    func appear() {
        isActive = true
        content.selectedMonth = nil
        content.selectedDay = nil
        refresh()
    }

    /// 退出去时停表。快照与正在看的月份、日子留着：页面往右滑出去的那一小会儿还要画着原来的内容，下次进来时再重置。
    func disappear() {
        isActive = false
        timer?.invalidate()
        timer = nil
    }

    /// 退一级：单日详情回月日历，月日历回月列表；已经在月列表时返回 false，由窗口退回概览。
    func goBack() -> Bool {
        if content.selectedDay != nil {
            content.selectedDay = nil
            return true
        }
        if content.selectedMonth != nil {
            content.selectedMonth = nil
            return true
        }
        return false
    }

    /// 页面视图；月列表页头的返回调 `back` 退回概览。
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

    /// 取最新快照；页面显示着时排下一次。退出去之后 (滑出动画里发出的命令) 只刷新内容，不再把停掉的定时器拉起来。
    private func refresh() {
        content.snapshot = model.currentSnapshot()
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
