#if DEBUG
import AppKit
import SwiftUI
import WageCore

/// 离屏渲染桌面悬浮小牛的各个档位与贴边收起的样子 (PNG)，和设计稿 QB602 对照用。只在 Debug 构建里。
/// 状态在内存里用核心命令造出来：2026-11-02 完成引导，发薪日 15 号遇休息日提前 (11-13 周五发)。
/// 每张画在设计稿同款 240×340 的桌面渐变底上；另有深色桌面底的几张，检查深色模式下是否可读。
///
/// 用法：`WAGETICK_RENDER_ENTRY=wagetick_render_floating_cow_previews scripts/render-panel-previews.sh build/floating-cow-previews`。
@_cdecl("wagetick_render_floating_cow_previews")
public func renderFloatingCowPreviews(_ directory: UnsafePointer<CChar>) {
    let url = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        AppFont.register()
        FloatingCowPreviews.renderAll(to: url)
    }
}

@MainActor
private enum FloatingCowPreviews {
    /// 设计稿 Desktop 的浅色渐变。
    private static let lightDesktop = [Color(red: 0xD7 / 255, green: 0xDE / 255, blue: 0xEA / 255), Color(red: 0xEA / 255, green: 0xDF / 255, blue: 0xD0 / 255)]
    /// 深色模式桌面。
    private static let darkDesktop = [Color(white: 0.12), Color(white: 0.2)]

    static func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let state = try withPayday()
            let scenes: [(String, Int, Int, (FloatingCow) -> AnyView, [Color])] = [
                ("1-far-off", 10, 22, expanded, lightDesktop),
                ("2-within-two-weeks", 11, 5, expanded, lightDesktop),
                ("2b-soon", 11, 11, expanded, lightDesktop),
                ("3-tomorrow", 11, 12, expanded, lightDesktop),
                ("4-payday", 11, 13, expanded, lightDesktop),
                ("4b-just-paid", 10, 16, expanded, lightDesktop),
                ("5-docked-right", 11, 5, docked(.right), lightDesktop),
                ("5b-docked-left", 11, 5, docked(.left), lightDesktop),
                ("5c-docked-right-tomorrow", 11, 12, docked(.right), lightDesktop),
                ("dark-2-within-two-weeks", 11, 5, expanded, darkDesktop),
                ("dark-4-payday", 11, 13, expanded, darkDesktop),
                ("dark-5-docked-right", 11, 5, docked(.right), darkDesktop),
            ]
            for (name, month, day, view, background) in scenes {
                guard let cow = snapshot(of: state, at: moment(month, day)).floatingCow else {
                    print("\(name)：快照里没有悬浮小牛")
                    continue
                }
                let file = directory.appending(path: "\(name).png")
                try render(desktop(view(cow), colors: background), to: file)
                print(file.path)
            }
        } catch {
            print("渲染失败：\(error)")
        }
    }

    private static func expanded(_ cow: FloatingCow) -> AnyView {
        AnyView(FloatingCowCanvas(cow: cow))
    }

    private static func docked(_ edge: FloatingCowEdge) -> (FloatingCow) -> AnyView {
        { cow in
            AnyView(FloatingCowPeek(pill: cow.pill, side: edge).frame(width: 240, height: 340, alignment: edge == .left ? .leading : .trailing))
        }
    }

    /// 设计稿同款 240×340 圆角桌面，小牛贴右下 (收起时贴左或右边、垂直居中)。
    private static func desktop(_ content: AnyView, colors: [Color]) -> some View {
        content
            .frame(width: 240, height: 340, alignment: .bottomTrailing)
            .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(12)
    }

    private static func withPayday() throws -> AppState {
        let schedule = WorkSchedule(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0),
            lunch: LunchBreak(start: TimeOfDay(hour: 12, minute: 0), end: TimeOfDay(hour: 13, minute: 0))
        )
        let input = OnboardingInput(salary: 21000, schedule: schedule, launchAtLogin: false)
        let onboarded = try apply(.completeOnboarding(input), to: AppState(), at: moment(11, 2)).state
        return try apply(.setPayday(Payday(dayOfMonth: 15, shift: .earlier)), to: onboarded, at: moment(11, 2)).state
    }

    private static func moment(_ month: Int, _ day: Int) -> Moment {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 15, minute: 0))!
        return Moment(date: date, timeZone: zone)
    }

    /// 纯 SwiftUI 画面，`ImageRenderer` 按 2 倍渲染。
    private static func render(_ view: some View, to file: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: file)
    }
}
#endif
