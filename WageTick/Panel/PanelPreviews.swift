#if DEBUG
import AppKit
import SwiftUI
import WageCore

/// 离屏渲染面板与两个表单的各个状态，存成 PNG，和设计稿 (P2、F5、F6 · 760，页脚距发薪) 对照用。只在 Debug 构建里。
/// 状态全部在内存里用核心命令造出来 (2026 年 11 月，月薪 21000、10:00 至 18:00、饭点 12:00 至 13:00，日薪 1000)，
/// 不起菜单栏、不读写 state.json，可以和正在跑的 App 同时用。
///
/// 入口是 C 符号 `wagetick_render_panel_previews(目录)`：Debug 构建关掉 hardened runtime 后，
/// 用 `DYLD_INSERT_LIBRARIES` 注入一个在加载时调用它的小 dylib，渲染完直接退出，`main` 不会跑。
@_cdecl("wagetick_render_panel_previews")
public func renderPanelPreviews(_ directory: UnsafePointer<CChar>) {
    let url = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        AppFont.register()
        PanelPreviews.renderAll(to: url)
    }
}

@MainActor
private enum PanelPreviews {
    static func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            for (name, view) in try scenes() {
                let file = directory.appending(path: "\(name).png")
                try render(view, to: file)
                print(file.path)
            }
        } catch {
            print("渲染失败：\(error)")
        }
    }

    /// 文件名与要渲染的视图。
    private static func scenes() throws -> [(String, AnyView)] {
        let base = try withGoals(onboarded())
        let fined = try at(base, day: 5, 15, 0) {
            try $0.send(.addDeduction(DeductionInput(amount: .fixed(50), reason: .late, note: "地铁又晚了五分钟")))
        }
        let unpaid = try at(fined, day: 5, 18, 0) { try $0.send(.startUnpaidWork) }
        let middle = Leave(start: TimeOfDay(hour: 14, minute: 0), end: TimeOfDay(hour: 16, minute: 0), deductionPercent: Decimal(string: "28.57")!)
        let middleLeave = try at(base, day: 5, 9, 0) { try $0.send(.setLeave(middle)) }
        let firstHalfLeave = try at(try onboarded(), day: 5, 9, 0) {
            try $0.send(.setLeave(Leave(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 12, minute: 0), deductionPercent: 50)))
        }
        // 发薪日每月 15 号、遇休息日提前：11-15 是周日，提前到 13 日 (周五)。
        let payday = try at(base, day: 2, 9, 0) { try $0.send(.setPayday(Payday(dayOfMonth: 15, shift: .earlier))) }
        let percentItem = try at(base, day: 5, 15, 0) {
            try $0.send(.addDeduction(DeductionInput(amount: .percentOfDailyWage(10), reason: .late, note: "地铁又晚了五分钟")))
        }
        return [
            ("P2-working", panel(base, day: 5, 15, 0)),
            ("P2-off-work", panel(base, day: 5, 18, 30)),
            ("P2-unpaid-work", panel(unpaid, day: 5, 19, 5, 12)),
            // 5 日 18:00 开始没停，过了零点 6 日 00:30 仍在白干中 (6 日 10:00 计划上班时自动停止)。
            ("P2-unpaid-work-past-midnight", panel(unpaid, day: 6, 0, 30)),
            ("P2-off-work-fined", panel(fined, day: 5, 18, 30)),
            ("P2-rest-day", panel(base, day: 7, 10, 12, 40)),
            ("P2-first-half-leave-no-goal", panel(firstHalfLeave, day: 5, 15, 0)),
            ("P2-middle-leave", panel(middleLeave, day: 5, 15, 0)),
            ("P2-payday-countdown", panel(payday, day: 5, 15, 0)),
            ("P2-payday-tomorrow", panel(payday, day: 12, 15, 0)),
            ("P2-payday-today", panel(payday, day: 13, 15, 0)),
            // 目标达成庆祝动画 (设计稿「弹窗-目标达成」)：截在弹出后约 0.3 秒，彩纸还在落。
            ("P2-goal-celebration", panel(base, day: 5, 15, 0, celebration: GoalCelebration(goalID: 1, goalName: "Switch 2"))),
            ("F5-add", panel(base, day: 5, 15, 0, route: .deduction(.add))),
            ("F5-edit-fixed", panel(fined, day: 5, 15, 0, route: .deduction(.edit(firstDeduction(fined, day: 5))))),
            ("F5-edit-percent", panel(percentItem, day: 5, 15, 0, route: .deduction(.edit(firstDeduction(percentItem, day: 5))))),
            ("F6-request", panel(base, day: 5, 9, 0, route: .leave(.request))),
            ("F6-edit-middle", panel(middleLeave, day: 5, 9, 0, route: .leave(.edit(middle)))),
        ]
    }

    // MARK: 造状态

    /// 11 月 2 日 (周一) 早上完成引导的状态。
    private static func onboarded() throws -> AppState {
        let schedule = WorkSchedule(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0),
            lunch: LunchBreak(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 13, minute: 0))
        )
        let input = OnboardingInput(salary: 21000, schedule: schedule, launchAtLogin: false)
        return try apply(.completeOnboarding(input), to: AppState(), at: moment(day: 2, 9, 0)).state
    }

    /// 一个累计中、两个排队中的目标 (设计稿 P2)。
    private static func withGoals(_ state: AppState) throws -> AppState {
        try at(state, day: 2, 9, 0) {
            try $0.send(.createGoal(name: "Switch 2", amount: 10000))
            try $0.send(.createGoal(name: "去趟大理", amount: 8000))
            try $0.send(.createGoal(name: "跑路基金", amount: 50000))
        }
    }

    /// 在 11 月 `day` 日的某一刻依次执行命令，返回执行后的状态。
    private static func at(
        _ state: AppState, day: Int, _ hour: Int, _ minute: Int, _ commands: (inout Sender) throws -> Void
    ) throws -> AppState {
        var sender = Sender(state: state, now: moment(day: day, hour, minute))
        try commands(&sender)
        return sender.state
    }

    private struct Sender {
        var state: AppState
        let now: Moment

        mutating func send(_ command: Command) throws {
            state = try apply(command, to: state, at: now).state
        }
    }

    private static func moment(day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Moment {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
        return Moment(date: date, timeZone: zone)
    }

    private static func firstDeduction(_ state: AppState, day: Int) -> DeductionItem {
        guard case .attendance(let attendance) = snapshot(of: state, at: moment(day: day, 15, 0)).panel?.body,
              let item = attendance.deductions.first else { fatalError("预览状态里没有扣钱") }
        return item
    }

    // MARK: 视图

    /// 与 `TodayPanelWindowController` 相同的面板尺寸 (窗口固定尺寸减去标题栏)，加圆角描边便于对照；命令只试算，不保存。
    private static func panel(
        _ state: AppState, day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0, route: PanelRoute = .home,
        celebration: GoalCelebration? = nil
    ) -> AnyView {
        let now = moment(day: day, hour, minute, second)
        let snap = snapshot(of: state, at: now)
        let content = TodayPanelContent()
        content.panel = snap.panel
        content.status = snap.today?.status
        content.leaveForm = snap.leaveForm
        content.route = route
        content.celebration = celebration
        let actions = PanelActions(
            dryRun: { command in
                Result { () throws(CommandError) in snapshot(of: try apply(command, to: state, at: now).state, at: now) }
            },
            send: { _ throws(CommandError) in }
        )
        let navigation = PanelNavigation(openHistory: {}, openGoals: {}, openSettings: {})
        return AnyView(
            TodayPanelView(content: content, actions: actions, navigation: navigation)
                .frame(height: WindowMetrics.size.height - WindowChrome.Titlebar.standard.height)
                .clipShape(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius).strokeBorder(Palette.line, lineWidth: 1))
                .padding(24)
                .background(Color.white)
        )
    }

    /// 放进屏幕外的窗口里排版再截图：输入框是 AppKit 控件，`ImageRenderer` 画不出来。
    /// 已知瑕疵：带描边的胶囊 (扣钱原因标签) 截出来两侧会多出竖线，`ImageRenderer` 画的没有，是这种截图方式的问题。
    private static func render(_ view: AnyView, to file: URL) throws {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        // 让 onAppear 里的聚焦、布局跑完一轮。
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        try rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}
#endif
