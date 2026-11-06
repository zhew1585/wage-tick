#if DEBUG
import AppKit
import SwiftUI

/// 离屏渲染引导两步的几个状态 (含双休、大小周两种休息模式)，存成 PNG，和设计稿 (P1 引导 · 1、2 · 760) 对照用。只在 Debug 构建里。
/// `AppModel` 读写临时目录里的空状态 (用完删掉)，不碰 state.json；试算按此刻与空节假日表。
///
/// 入口是 C 符号 `wagetick_render_onboarding_previews(目录)`，用法同 `PanelPreviews`：
/// `WAGETICK_RENDER_ENTRY=wagetick_render_onboarding_previews scripts/render-panel-previews.sh build/onboarding-previews`。
@_cdecl("wagetick_render_onboarding_previews")
public func renderOnboardingPreviews(_ directory: UnsafePointer<CChar>) {
    let url = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        AppFont.register()
        OnboardingPreviews.renderAll(to: url)
    }
}

@MainActor
private enum OnboardingPreviews {
    static func renderAll(to directory: URL) {
        let stateDirectory = FileManager.default.temporaryDirectory.appending(path: "wagetick-onboarding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: stateDirectory) }
        let model = AppModel(store: StateStore(directory: stateDirectory))
        let scenes: [(String, OnboardingView)] = [
            ("P1-1-salary-empty", OnboardingView(model: model) {}),
            ("P1-1-salary-filled", OnboardingView(model: model, salaryText: "20000") {}),
            ("P1-1-rest-alternating", OnboardingView(model: model, salaryText: "20000", restMode: .bigWeekNow) {}),
            ("P1-2-schedule", OnboardingView(model: model, step: .schedule, salaryText: "20000") {}),
            ("P1-2-schedule-alternating", OnboardingView(model: model, step: .schedule, salaryText: "20000", restMode: .bigWeekNow) {}),
        ]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, view) in scenes {
                let file = directory.appending(path: "\(name).png")
                try render(view, to: file)
                print(file.path)
            }
        } catch {
            print("渲染失败：\(error)")
        }
    }

    /// 放进屏幕外的窗口里排版再截图：输入框是 AppKit 控件，`ImageRenderer` 画不出来。
    private static func render(_ view: OnboardingView, to file: URL) throws {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: WindowMetrics.size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw RenderError.noBitmap }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw RenderError.noBitmap }
        try png.write(to: file)
    }

    private enum RenderError: Error {
        /// 截不出位图或编码不成 PNG。
        case noBitmap
    }
}
#endif
