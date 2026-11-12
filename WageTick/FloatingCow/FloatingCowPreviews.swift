#if DEBUG
import AppKit
import SwiftUI
import WageCore

/// 离屏渲染桌面悬浮小牛的各个档位与贴边收起的样子 (PNG)，和设计稿 QB602 对照用。只在 Debug 构建里。
/// 状态在内存里用核心命令造出来：2026-11-02 完成引导，作息 10:00 至 18:00 (饭点 12:00 至 13:00)，发薪日 15 号遇休息日提前 (11-13 周五发)。
/// 每张画在设计稿同款 240×340 的桌面渐变底上；另有深色桌面底的几张，检查深色模式下是否可读。
/// 每个动作另外逐帧渲染一个完整循环到 `frames-<动作>/` (30 帧每秒)，拼视频：
/// `ffmpeg -framerate 30 -i frames-paid/%03d.png -pix_fmt yuv420p paid.mp4`。
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
            // (文件名, 月, 日, 时, 分, 画法, 桌面底色)
            let scenes: [(String, Int, Int, Int, Int, (FloatingCow) -> AnyView, [Color])] = [
                ("1-before-work", 11, 5, 9, 15, expanded, lightDesktop),
                ("2-working", 11, 5, 15, 46, expanded, lightDesktop),
                ("3-lunch", 11, 5, 12, 28, expanded, lightDesktop),
                ("4-off-work", 11, 5, 19, 0, expanded, lightDesktop),
                ("5-rest-day", 11, 7, 15, 0, expanded, lightDesktop),
                ("6-payday-soon", 11, 11, 15, 0, expanded, lightDesktop),
                ("7-payday-tomorrow", 11, 12, 15, 0, expanded, lightDesktop),
                ("8-payday", 11, 13, 15, 0, expanded, lightDesktop),
                ("9-docked-right", 11, 5, 15, 46, docked(.right), lightDesktop),
                ("9b-docked-left", 11, 5, 15, 46, docked(.left), lightDesktop),
                ("9c-docked-off-work", 11, 5, 19, 0, docked(.right), lightDesktop),
                ("dark-2-working", 11, 5, 15, 46, expanded, darkDesktop),
                ("dark-8-payday", 11, 13, 15, 0, expanded, darkDesktop),
                ("dark-9-docked-right", 11, 5, 15, 46, docked(.right), darkDesktop),
            ]
            for (name, month, day, hour, minute, view, background) in scenes {
                guard let cow = snapshot(of: state, at: moment(month, day, hour, minute)).floatingCow else {
                    print("\(name)：快照里没有悬浮小牛")
                    continue
                }
                let file = directory.appending(path: "\(name).png")
                try render(desktop(view(cow), colors: background), to: file)
                print(file.path)
            }
            // 每个动作一个完整循环的逐帧 (发薪当天连同彩带取 2.2 秒)，气泡用上班中的。
            if let working = snapshot(of: state, at: moment(11, 5, 15, 46)).floatingCow {
                let acts = FloatingCowPose.allCases.map(CowAct.pose) + [.crying]
                for act in acts {
                    let loop = act == .pose(.paid) ? CowConfetti.period : CowRigs.rig(for: act).period
                    try renderLoop(working, act: act, seconds: loop, to: directory.appending(path: "frames-\(name(of: act))"))
                }
            }
        } catch {
            print("渲染失败：\(error)")
        }
    }

    private static func name(of act: CowAct) -> String {
        switch act {
        case .pose(let pose): "\(pose)"
        case .crying: "crying"
        }
    }

    private static func renderLoop(_ cow: FloatingCow, act: CowAct, seconds: TimeInterval, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let count = Int((seconds / CowRig.sampleInterval).rounded())
        for index in 0..<count {
            let view = FloatingCowCanvas(cow: cow, act: act, time: Double(index) * CowRig.sampleInterval)
            try render(desktop(AnyView(view), colors: lightDesktop), to: directory.appending(path: String(format: "%03d.png", index)))
        }
        print(directory.path)
    }

    private static func expanded(_ cow: FloatingCow) -> AnyView {
        AnyView(FloatingCowCanvas(cow: cow, time: 0))
    }

    private static func docked(_ edge: FloatingCowEdge) -> (FloatingCow) -> AnyView {
        { cow in
            AnyView(FloatingCowPeek(pill: cow.pill, side: edge, time: 0).frame(width: 240, height: 340, alignment: edge == .left ? .leading : .trailing))
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

    private static func moment(_ month: Int, _ day: Int, _ hour: Int = 15, _ minute: Int = 0) -> Moment {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
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
