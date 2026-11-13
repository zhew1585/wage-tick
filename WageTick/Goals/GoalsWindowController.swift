import AppKit
import Observation
import SwiftUI
import WageCore

/// 目标窗口当前要展示的内容，由窗口控制器按快照刷新；`route` 是窗口里正在显示的页面，视图切页时改它。
@MainActor
@Observable
final class GoalsContent {
    var list = GoalList.empty
    var route = GoalsRoute.queue

    /// 按快照填好各项。
    func update(from snap: Snapshot) {
        list = snap.goals ?? .empty
    }
}

/// 目标窗口里的页面：攒钱队列 (首页)、已到手、新建或编辑目标的表单。三页在同一个窗口里原地切换。
enum GoalsRoute: Equatable {
    case queue
    case earned
    case form(GoalFormView.Mode)
}

/// 目标窗口 (PRD F8，页面 P3)，从左键菜单、主菜单「目标 ⌘2」或面板目标区打开。外观见 `PageWindow`。
/// 只在窗口可见时每秒刷新一次，让累计中目标的累计额跟着走。重新打开时回到攒钱队列；头图上的「返回」关窗。
@MainActor
final class GoalsWindowController: NSObject, NSWindowDelegate {
    private static let refreshInterval: TimeInterval = 1

    private let model: AppModel
    private let content = GoalsContent()
    private lazy var window: NSWindow = makeWindow()
    private lazy var placement = WindowPlacement(window: window, name: "Goals")
    private var timer: Timer?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        refresh()
        NSApp.activate()
        if !window.isVisible && !window.isMiniaturized {
            content.route = .queue
            placement.place()
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
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

    private func makeWindow() -> NSWindow {
        let view = GoalsView(
            content: content,
            send: { [weak self] (command: Command) throws(CommandError) in try self?.send(command) },
            close: { [weak self] in self?.window.performClose(nil) }
        )
        return PageWindow.make(title: "目标", rootView: view, delegate: self)
    }
}
