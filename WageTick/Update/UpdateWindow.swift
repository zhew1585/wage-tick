import AppKit
import Observation
import SwiftUI

/// 更新窗口要显示的一屏 (设计稿「App 内更新 · 4 个界面」)。每一屏带着它的按钮动作；点红色关闭按钮等同于 `dismiss`。
enum UpdateScreen {
    /// ① 发现新版本：版本号、当前版本、更新内容；以后再说 / 下载更新。
    case found(version: String, current: String, notes: [String], later: () -> Void, download: () -> Void)
    /// ② 下载中：已下载与总大小 (总大小未知时为 0)；取消下载。
    case downloading(version: String, received: UInt64, expected: UInt64, cancel: () -> Void)
    /// ② 下载完在解压，没有可点的按钮。
    case extracting(version: String)
    /// ③ 已准备好：自动更新下载完也弹这个；稍后自行重启 / 立即重启。
    case ready(version: String, notes: [String], later: () -> Void, restart: () -> Void)
    /// ④ 已是最新版。
    case upToDate(current: String, ok: () -> Void)
    /// 检查或下载出错 (设计稿之外，沿用 ④ 的样子)。
    case failed(message: String, ok: () -> Void)

    /// 点关闭按钮时做什么：等同于「以后再说 / 取消 / 稍后 / 好」。
    var dismiss: (() -> Void)? {
        switch self {
        case .found(_, _, _, let later, _): later
        case .downloading(_, _, _, let cancel): cancel
        case .extracting: nil
        case .ready(_, _, let later, _): later
        case .upToDate(_, let ok), .failed(_, let ok): ok
        }
    }
}

/// 更新窗口：宽 360、高随内容，样子同其他窗口 (米白底、透明标题栏、红绿灯)，见 `UpdateView`。
/// 同一时间只有一个，换屏时原地刷新；点按钮或关闭都会先把这一屏的回调交还给 Sparkle 再关窗。
///
/// 用法：`UpdateWindowController.shared.show(.ready(...))`，`close()` 关窗而不触发回调。
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()

    @Observable
    final class Model {
        var screen: UpdateScreen?
    }

    private let model = Model()
    private lazy var window: NSWindow = makeWindow()
    /// 已经交还了回调 (点了按钮或代码关窗)，关窗时不再触发 `dismiss`。
    private var handled = false

    func show(_ screen: UpdateScreen) {
        model.screen = screen
        handled = false
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// 刷新当前一屏 (如下载进度)，不抢焦点。窗口没开时不弹出来。
    func update(_ screen: UpdateScreen) {
        guard window.isVisible else { return }
        model.screen = screen
    }

    var isShowing: Bool { window.isVisible }

    func close() {
        handled = true
        window.close()
    }

    /// 按钮回调：先关窗，再交还给 Sparkle。
    fileprivate func perform(_ action: @escaping () -> Void) {
        close()
        action()
    }

    func windowWillClose(_ notification: Notification) {
        guard !handled else { return }
        handled = true
        model.screen?.dismiss?()
    }

    private func makeWindow() -> NSWindow {
        let view = UpdateView(model: model) { [weak self] action in self?.perform(action) }
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        controller.safeAreaRegions = []
        let window = NSWindow(contentViewController: controller)
        window.title = "更新"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = NSColor(Palette.bg)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}

/// 更新窗口的内容：小牛 88、标题 20/700、说明 13 muted，按屏放更新内容卡片、进度条与按钮 (设计稿「App 内更新 · 4 个界面」)。
struct UpdateView: View {
    let model: UpdateWindowController.Model
    let perform: (@escaping () -> Void) -> Void

    var body: some View {
        VStack(spacing: Spacing.s14) {
            if let screen = model.screen {
                content(screen)
            }
        }
        .padding(EdgeInsets(top: WindowChrome.Titlebar.standard.height + Spacing.s6, leading: Spacing.s24, bottom: Spacing.s24, trailing: Spacing.s24))
        .frame(width: WindowMetrics.size.width)
        .background(Palette.bg)
    }

    @ViewBuilder
    private func content(_ screen: UpdateScreen) -> some View {
        switch screen {
        case .found(let version, let current, let notes, let later, let download):
            heading("有新版本啦", "\(version) · 你现在用的是 \(current)")
            notesCard(notes)
            buttons(secondary: ("以后再说", .clock, later), primary: ("下载更新", .downloadSimple, download))
            footnote("打开了自动更新的话，新版本会在后台自己下载")
        case .downloading(let version, let received, let expected, let cancel):
            heading("正在下载 \(version)", "下载完会先问你，不会突然重启")
            progress(received: received, expected: expected)
            buttons(secondary: ("取消下载", .x, cancel), primary: nil)
        case .extracting(let version):
            heading("正在准备 \(version)", "马上就好")
            progress(received: 1, expected: 1)
        case .ready(let version, let notes, let later, let restart):
            heading("新版本准备好了", "\(version) 已下载并校验完成，重启后生效")
            notesCard(notes)
            buttons(secondary: ("稍后自行重启", .clock, later), primary: ("立即重启", .arrowClockwise, restart))
            footnote("选稍后的话，下次退出时自动装好；也可以在菜单栏小牛的菜单里点「重启以完成更新」")
        case .upToDate(let current, let ok):
            heading("已经是最新版", "\(current) · 刚刚检查过")
            buttons(secondary: nil, primary: ("好", .check, ok))
        case .failed(let message, let ok):
            heading("没能完成更新", message)
            buttons(secondary: nil, primary: ("好", .check, ok))
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: Spacing.s14) {
            Image(.cowMascot).resizable().scaledToFit().frame(width: 88, height: 88).accessibilityHidden(true)
            VStack(spacing: Spacing.s6) {
                Text(title).font(AppFont.ui(20, .bold)).foregroundStyle(Palette.ink)
                Text(subtitle).font(AppFont.body).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            }
        }
    }

    /// 更新内容卡片：surface 底、圆角 10，每条前面一个 accent 圆点；没有内容时不显示。
    @ViewBuilder
    private func notesCard(_ notes: [String]) -> some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                Text("更新内容").font(AppFont.captionSemibold).foregroundStyle(Palette.muted)
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                        Circle().fill(Palette.accent).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        Text(note).font(AppFont.body).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r10))
        }
    }

    /// 进度条 8 高 (line 底、accent 填充)，下面左边已下载 / 总大小，右边百分比。
    private func progress(received: UInt64, expected: UInt64) -> some View {
        let ratio = expected > 0 ? min(Double(received) / Double(expected), 1) : 0
        return VStack(spacing: Spacing.s8) {
            GeometryReader { geometry in
                Capsule().fill(Palette.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Palette.accent).frame(width: geometry.size.width * ratio)
                    }
            }
            .frame(height: 8)
            HStack {
                Text(expected > 0 ? "\(Self.megabytes(received)) / \(Self.megabytes(expected))" : Self.megabytes(received))
                    .font(AppFont.numCaption).foregroundStyle(Palette.muted)
                Spacer()
                Text("\(Int(ratio * 100))%").font(AppFont.num(12, .semibold)).foregroundStyle(Palette.accent)
            }
        }
        .padding(.top, Spacing.s6)
    }

    private func buttons(secondary: (String, Phosphor, () -> Void)?, primary: (String, Phosphor, () -> Void)?) -> some View {
        HStack(spacing: Spacing.s10) {
            if let (title, icon, action) = secondary {
                Button { perform(action) } label: { Label { Text(title) } icon: { PhosphorIcon(icon) } }
                    .buttonStyle(.secondary(fullWidth: true))
                    .keyboardShortcut(.cancelAction)
            }
            if let (title, icon, action) = primary {
                Button { perform(action) } label: { Label { Text(title) } icon: { PhosphorIcon(icon) } }
                    .buttonStyle(.primary(fullWidth: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, Spacing.s4)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(AppFont.ui(11)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 字节数写成「3.2 MB」。
    private static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }
}
