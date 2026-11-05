#if DEBUG
import AppKit
import SwiftUI
import WageCore

/// 离屏渲染目标、历史 (月列表、月日历、单日详情)、设置几页，存成 PNG，和设计稿 (P3 至 P6 · 760) 对照用。只在 Debug 构建里。
/// 目标与历史的状态在内存里用核心命令造出来 (2026 年 11 月 5 日 15:00，月薪 20000、10:00 至 18:00、午休 12:00 至 13:00，
/// 30 日改成不上班后应出勤 20 天、日薪 1000)；设置页要一个 `AppModel`，用临时目录里的状态文件 (此刻真实时间)。
/// 不起菜单栏、不读写正在用的 state.json，可以和正在跑的 App 同时用。
///
/// 入口是 C 符号 `wagetick_render_page_previews(目录)`，用法见 `scripts/render-page-previews.sh` (做法同 `PanelPreviews`)。
@_cdecl("wagetick_render_page_previews")
public func renderPagePreviews(_ directory: UnsafePointer<CChar>) {
    let url = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        AppFont.register()
        PagePreviews.renderAll(to: url)
    }
}

@MainActor
private enum PagePreviews {
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

    private static let today = LocalDate(year: 2026, month: 11, day: 5)

    private static func scenes() throws -> [(String, AnyView)] {
        let state = try november()
        let now = moment(day: 5, 15, 0)
        let snap = snapshot(of: state, at: now)
        return [
            ("P3-goals", goals(snap)),
            ("P3-goals-empty", goals(snapshot(of: try onboarded(), at: now))),
            ("P4-history", history(snap)),
            ("P5-calendar", history(snap, month: today.yearMonth)),
            ("P5-calendar-october", history(snap, month: YearMonth(year: 2026, month: 10))),
            ("P5-day-detail", history(snap, month: today.yearMonth, day: LocalDate(year: 2026, month: 11, day: 4))),
            ("P5-day-detail-today", history(snap, month: today.yearMonth, day: today)),
            ("P6-settings", try settings()),
        ]
    }

    // MARK: 造状态

    /// 10 月 15 日 (周四) 早上完成引导，月薪 20000。
    private static func onboarded() throws -> AppState {
        let schedule = WorkSchedule(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0),
            lunch: LunchBreak(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 13, minute: 0))
        )
        let input = OnboardingInput(monthlySalary: 20000, schedule: schedule, launchAtLogin: false)
        return try apply(.completeOnboarding(input), to: AppState(), at: moment(month: 10, day: 15, 9, 0)).state
    }

    /// 设计稿 P5 的 11 月：4 日迟到扣 50、18:00 至 19:42 白干，今天 (5 日) 扣 50，11 日下午假，30 日改成不上班；
    /// 目标：10 月达成两个，11 月 2 日起一个累计中 (Switch 2)、三个排队中。
    private static func november() throws -> AppState {
        var state = try onboarded()
        state = try at(state, month: 10, day: 15, 9, 0) {
            try $0.send(.createGoal(name: "AirPods Pro", amount: 1899))
            try $0.send(.createGoal(name: "人体工学椅", amount: 2399))
        }
        state = try at(state, month: 10, day: 30, 9, 0) { try $0.send(.advance) }
        state = try at(state, day: 2, 9, 0) {
            try $0.send(.createGoal(name: "Switch 2", amount: 10000))
            try $0.send(.createGoal(name: "去趟大理", amount: 8000))
            try $0.send(.createGoal(name: "换台 MacBook", amount: 15000))
            try $0.send(.createGoal(name: "跑路基金", amount: 100000))
        }
        let late = DeductionInput(amount: .fixed(50), reason: .late, note: "地铁又晚了五分钟")
        state = try at(state, day: 4, 15, 0) { try $0.send(.addDeduction(late)) }
        state = try at(state, day: 4, 18, 0) { try $0.send(.startUnpaidWork) }
        state = try at(state, day: 4, 19, 42) { try $0.send(.stopUnpaidWork) }
        return try at(state, day: 5, 11, 0) {
            try $0.send(.advance)
            try $0.send(.addDeduction(late))
            try $0.send(.editDay(LocalDate(year: 2026, month: 11, day: 11), .requestLeave(Leave(period: .afternoon, deductionPercent: 50))))
            try $0.send(.editDay(LocalDate(year: 2026, month: 11, day: 30), .setOverride(.dayOff)))
        }
    }

    private static func at(
        _ state: AppState, month: Int = 11, day: Int, _ hour: Int, _ minute: Int, _ commands: (inout Sender) throws -> Void
    ) throws -> AppState {
        var sender = Sender(state: state, now: moment(month: month, day: day, hour, minute))
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

    private static func moment(month: Int = 11, day: Int, _ hour: Int, _ minute: Int) -> Moment {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        return Moment(date: date, timeZone: zone)
    }

    // MARK: 视图

    private static func goals(_ snap: Snapshot) -> AnyView {
        let content = GoalsContent()
        content.update(from: snap)
        return page(GoalsView(content: content, send: { _ throws(CommandError) in }, close: {}))
    }

    private static func history(_ snap: Snapshot, month: YearMonth? = nil, day: LocalDate? = nil) -> AnyView {
        let content = HistoryContent()
        content.snapshot = snap
        content.selectedMonth = month
        content.selectedDay = day
        let actions = PanelActions(dryRun: { _ in .success(snap) }, send: { _ throws(CommandError) in })
        return page(HistoryView(content: content, actions: actions, close: {}))
    }

    /// 设置页：临时目录里一个刚完成引导的状态 (此刻真实时间)，不碰正在用的状态文件。
    private static func settings() throws -> AnyView {
        let directory = FileManager.default.temporaryDirectory.appending(path: "wagetick-page-previews-\(UUID().uuidString)")
        let model = AppModel(store: StateStore(directory: directory))
        let schedule = WorkSchedule(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0),
            lunch: LunchBreak(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 13, minute: 0))
        )
        try model.send(.completeOnboarding(OnboardingInput(monthlySalary: 20000, schedule: schedule, launchAtLogin: true)))
        let form = SettingsFormModel(model: model, menuBar: nil, notifier: SystemNotifier(openPanel: {}))
        form.reload()
        defer { try? FileManager.default.removeItem(at: directory) }
        return page(SettingsView(form: form, close: {}))
    }

    /// 与窗口相同的固定尺寸与底色，四周留白、细描边便于对照。红绿灯是系统画的，这里不画。
    private static func page(_ view: some View) -> AnyView {
        let size = WindowMetrics.size
        return AnyView(
            view
                .frame(width: size.width, height: size.height)
                .background(Palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: Radius.r14))
                .overlay(RoundedRectangle(cornerRadius: Radius.r14).strokeBorder(Palette.line, lineWidth: 1))
                .padding(24)
                .background(Color.white)
        )
    }

    /// 放进屏幕外的窗口里排版再截图 (同 `PanelPreviews.render`)。
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        try rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}
#endif
