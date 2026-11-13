#if DEBUG
import AppKit
import SwiftUI

/// 离屏渲染更新窗口的每一屏 (含设计稿之外的解压中、出错)，存成 PNG，和设计稿「更新-1」至「更新-4」对照用。只在 Debug 构建里。
/// 不碰 Sparkle，按钮动作都是空的。
///
/// 入口是 C 符号 `wagetick_render_update_previews(目录)`，用法同 `PanelPreviews`：
/// `WAGETICK_RENDER_ENTRY=wagetick_render_update_previews scripts/render-panel-previews.sh build/update-previews`。
@_cdecl("wagetick_render_update_previews")
public func renderUpdatePreviews(_ directory: UnsafePointer<CChar>) {
    let url = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        AppFont.register()
        UpdatePreviews.renderAll(to: url)
    }
}

@MainActor
private enum UpdatePreviews {
    private static let notes = [
        "统计行加上距离周末，下一个休息日是法定节假日时叫距离放假",
        "扣款并到主数字下方的小字里",
        "大号小组件休息日、已下班时主内容放大",
    ]

    private static let screens: [(String, UpdateScreen)] = [
        ("U1-found", .found(version: "0.1.1", current: "0.1.0", notes: notes, later: {}, download: {})),
        ("U2-downloading", .downloading(version: "0.1.1", received: 3_200_000, expected: 8_600_000, cancel: {})),
        ("U2-extracting", .extracting(version: "0.1.1")),
        ("U3-ready", .ready(version: "0.1.1", notes: notes, later: {}, restart: {})),
        ("U4-up-to-date", .upToDate(current: "0.1.1", build: "42", ok: {})),
        ("U5-failed", .failed(message: "连不上更新服务器，检查一下网络再试", ok: {})),
    ]

    static func renderAll(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, screen) in screens {
                let file = directory.appending(path: "\(name).png")
                try render(screen, to: file)
                print(file.path)
            }
        } catch {
            print("渲染失败：\(error)")
        }
    }

    /// 放进屏幕外的窗口里排版再截图 (同 `PanelPreviews.render`)；四周留白、细描边便于对照，红绿灯是系统画的，这里不画。
    private static func render(_ screen: UpdateScreen, to file: URL) throws {
        let model = UpdateWindowController.Model()
        model.screen = screen
        let view = UpdateView(model: model) { _ in }
            .clipShape(RoundedRectangle(cornerRadius: Radius.r14))
            .overlay(RoundedRectangle(cornerRadius: Radius.r14).strokeBorder(Palette.line, lineWidth: 1))
            .padding(24)
            .background(Color.white)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: hosting.fittingSize),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        defer { window.orderOut(nil) }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
              let png = { hosting.cacheDisplay(in: hosting.bounds, to: rep); return rep.representation(using: .png, properties: [:]) }()
        else { throw RenderError.noBitmap }
        try png.write(to: file)
    }

    private enum RenderError: Error {
        /// 截不出位图或编码不成 PNG。
        case noBitmap
    }
}
#endif
