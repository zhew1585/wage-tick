#if DEBUG
import AppKit
import SwiftUI
import WageCore

/// 离屏渲染桌面小组件三种尺寸的各个状态，存成 PNG，和设计稿 (uRf1y) 对照用。只在 Debug 构建的 App 里，不进小组件扩展。
/// 状态与面板预览相同，全部在内存里用核心命令造出来 (2026 年 11 月，月薪 21000、10:00 至 18:00、饭点 12:00 至 13:00，日薪 1000)，
/// 不读写 state.json 与 widget.json。计时文字停在条目时刻。
/// 和真机小组件一样不注册打包的字体，用系统字体渲染。
///
/// 入口是 C 符号 `wagetick_render_widget_previews(目录)`，用法见 `scripts/render-widget-previews.sh`。
@_cdecl("wagetick_render_widget_previews")
public func renderWidgetPreviews(_ directory: UnsafePointer<CChar>) {
    let url = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        // 不注册打包的字体：真机小组件用系统字体 (见 `WageTickWidgets`)，预览跟它一致。
        WidgetPreviews.renderAll(to: url)
    }
}

@MainActor
private enum WidgetPreviews {
    static func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            for (name, state, now) in try scenes() {
                let snapshot = widgetSnapshot(of: state, at: now)
                for size in WidgetSize.allCases {
                    let file = directory.appending(path: "\(size)-\(name).png")
                    try render(snapshot, size: size, now: now.date, to: file)
                    print(file.path)
                }
            }
        } catch {
            print("渲染失败：\(error)")
        }
    }

    /// 文件名后缀、状态与此刻。
    private static func scenes() throws -> [(String, AppState, Moment)] {
        let plain = try onboarded()
        let base = try withGoals(plain)
        let unpaid = try at(base, day: 5, 18, 0) { try $0.send(.startUnpaidWork) }
        let unpaidDone = try at(unpaid, day: 5, 19, 30) { try $0.send(.stopUnpaidWork) }
        let middle = Leave(start: TimeOfDay(hour: 14, minute: 0), end: TimeOfDay(hour: 16, minute: 0), deductionPercent: Decimal(string: "28.57")!)
        let middleLeave = try at(base, day: 5, 9, 0) { try $0.send(.setLeave(middle)) }
        let fullDay = Leave(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0), deductionPercent: 100)
        let fullDayLeave = try at(base, day: 5, 9, 0) { try $0.send(.setLeave(fullDay)) }
        let fined = try at(base, day: 5, 11, 0) {
            try $0.send(.addDeduction(DeductionInput(amount: .fixed(50), reason: .late, note: "")))
        }
        return [
            ("working", base, moment(day: 5, 15, 0)),
            ("not-started", base, moment(day: 5, 9, 30)),
            ("lunch", base, moment(day: 5, 12, 30)),
            ("on-leave", middleLeave, moment(day: 5, 15, 0)),
            ("working-fined", fined, moment(day: 5, 15, 0)),
            ("off-work", base, moment(day: 5, 18, 30)),
            ("off-work-unpaid-summary", unpaidDone, moment(day: 5, 20, 0)),
            ("unpaid-work", unpaid, moment(day: 5, 19, 5, 12)),
            // 5 日 18:00 开始没停，过了零点 6 日 00:30 仍在白干中。
            ("unpaid-work-past-midnight", unpaid, moment(day: 6, 0, 30)),
            ("rest-day", base, moment(day: 7, 10, 0)),
            ("full-day-leave", fullDayLeave, moment(day: 5, 15, 0)),
            ("no-goal", plain, moment(day: 5, 15, 0)),
            ("setup", AppState(), moment(day: 5, 15, 0)),
        ]
    }

    // MARK: 造状态 (同 `PanelPreviews`)

    /// 11 月 2 日 (周一) 早上完成引导的状态。
    private static func onboarded() throws -> AppState {
        let schedule = WorkSchedule(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0),
            lunch: LunchBreak(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 13, minute: 0))
        )
        let input = OnboardingInput(monthlySalary: 21000, schedule: schedule, launchAtLogin: false)
        return try apply(.completeOnboarding(input), to: AppState(), at: moment(day: 2, 9, 0)).state
    }

    /// 一个累计中、两个排队中的目标 (设计稿大号)。
    private static func withGoals(_ state: AppState) throws -> AppState {
        try at(state, day: 2, 9, 0) {
            try $0.send(.createGoal(name: "Switch 2", amount: 10000))
            try $0.send(.createGoal(name: "去趟大理", amount: 8000))
            try $0.send(.createGoal(name: "跑路基金", amount: 50000))
        }
    }

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

    // MARK: 视图

    /// 设计稿尺寸、bg 底、圆角 22、line 描边，外面留白，和设计稿导出图一样摆。
    private static func render(_ snapshot: WidgetSnapshot, size: WidgetSize, now: Date, to file: URL) throws {
        let view = WidgetContentView(snapshot: snapshot, size: size, clock: WidgetClock(now: now, frozen: true))
            .frame(width: size.designSize.width, height: size.designSize.height)
            .background(Palette.bg)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.line, lineWidth: 1))
            .padding(24)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try png.write(to: file)
    }
}
#endif
