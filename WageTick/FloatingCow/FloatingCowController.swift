import AppKit
import Observation
import OSLog
import SwiftUI
import WageCore

/// 浮窗正在画什么：快照里的小牛内容，展开还是贴边收起。
@MainActor
@Observable
final class FloatingCowContent {
    enum Mode: Equatable {
        case expanded
        case collapsed(FloatingCowEdge)
    }

    var cow: FloatingCow?
    var mode = Mode.expanded
}

/// 浮窗的根视图：展开时画完整小牛，收起时画小条 + 探头。
struct FloatingCowRoot: View {
    let content: FloatingCowContent

    var body: some View {
        if let cow = content.cow {
            switch content.mode {
            case .expanded: FloatingCowCanvas(cow: cow)
            case .collapsed(let edge): FloatingCowPeek(pill: cow.pill, side: edge)
            }
        }
    }
}

/// 桌面悬浮小牛 (issue #21，设计稿方案 C)：显示、摆放、拖动贴边、悬停展开、单击与右键菜单。
/// 内容取自快照的 `floatingCow`，菜单栏每次刷新时经 `update(_:)` 交进来；nil 或有 App 全屏时收起浮窗。
/// 位置见 `FloatingCowSpot`：默认主屏右下角、Dock 上方，拖过之后记住；拖到屏幕左右边缘贴边收起成探头，
/// 鼠标移上去展开成完整小牛，移开收回。
@MainActor
final class FloatingCowController {
    struct Actions {
        let openTodayPanel: () -> Void
        let openSettings: () -> Void
        /// 右键菜单改了状态后让菜单栏 (以及经由它的浮窗) 立即刷新。
        let stateChanged: () -> Void
    }

    /// 贴边时查看鼠标位置的间隔：用轮询而不用 tracking area，鼠标停在透明留白上 (事件穿透) 时也判断得准。
    private static let hoverInterval: TimeInterval = 0.15
    /// 鼠标离开展开的小牛这么久才收回，免得擦边时来回闪。
    private static let collapseDelay: TimeInterval = 0.4

    private let model: AppModel
    private let actions: Actions
    private let content = FloatingCowContent()
    private lazy var panel = makePanel()
    private lazy var eventView = FloatingCowEventView(rootView: FloatingCowRoot(content: content))
    private lazy var fullScreen = FullScreenWatcher { [weak self] in self?.checkFullScreen() }
    private var spot: FloatingCowSpot?
    private var isFullScreenHidden = false
    private var hoverTimer: Timer?
    private var mouseLeftAt: Date?
    private var screensObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: AppIdentity.bundleID, category: "FloatingCow")

    init(model: AppModel, actions: Actions) {
        self.model = model
        self.actions = actions
        spot = FloatingCowSpot.load()
        // 上次贴着边：启动时就是收起的样子。
        if case .docked(let edge, _, _) = spot { content.mode = .collapsed(edge) }
        // 插拔外接屏、改排列或分辨率后坐标系会变，按停放位置重新摆一次，免得停在接缝上或看不见的地方。
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.applyFrame()
            }
        }
    }

    /// 菜单栏刷新时交来最新快照；内容没变时不重画。
    func update(_ snapshot: Snapshot) {
        _ = fullScreen
        // 收起期间不再查全屏；下次出现时重新查。
        if snapshot.floatingCow == nil { isFullScreenHidden = false }
        if content.cow != snapshot.floatingCow {
            content.cow = snapshot.floatingCow
            if panel.isVisible { applyFrame() }
        }
        updateVisibility()
    }

    // MARK: 显示与摆放

    /// 菜单栏刷新很频繁 (上班中每 0.1 秒)，这里只比较状态；全屏只在出现时和 `FullScreenWatcher` 回调时查。
    private func updateVisibility() {
        let wanted = content.cow != nil
        if wanted && !panel.isVisible && !isFullScreenHidden {
            applyFrame()
            isFullScreenHidden = currentScreen.map(FullScreenWatcher.hasFullScreenApp(on:)) ?? false
        }
        let shouldShow = wanted && !isFullScreenHidden
        if shouldShow && !panel.isVisible {
            panel.orderFrontRegardless()
        } else if !shouldShow && panel.isVisible {
            panel.orderOut(nil)
        }
        updateHoverTimer()
    }

    private func checkFullScreen() {
        isFullScreenHidden = content.cow != nil && (currentScreen.map(FullScreenWatcher.hasFullScreenApp(on:)) ?? false)
        updateVisibility()
    }

    private var currentScreen: NSScreen? {
        panel.screen ?? NSScreen.main
    }

    /// 按停放位置与当前样子 (展开、收起) 摆好浮窗。随便放的位置已不在任何屏幕上时退回默认位置。
    private func applyFrame() {
        switch spot {
        case .docked(let edge, let edgeX, let midY):
            if case .expanded = content.mode {
                setFrame(FloatingCowLayout.expandedFrame(at: .docked(edge: edge, edgeX: edgeX, midY: midY)))
            } else {
                content.mode = .collapsed(edge)
                setFrame(FloatingCowLayout.collapsedFrame(edge: edge, edgeX: edgeX, midY: midY, size: peekSize(edge)))
            }
        case .free, nil:
            content.mode = .expanded
            setFrame(spot.flatMap { FloatingCowLayout.expandedFrame(at: $0) } ?? FloatingCowLayout.defaultFrame())
        }
    }

    /// 收起的浮窗大小随小条上的字变 (「8 天」「28 天」「明天」)，单独量一次。
    private func peekSize(_ edge: FloatingCowEdge) -> CGSize {
        guard let cow = content.cow else { return .zero }
        return NSHostingView(rootView: FloatingCowPeek(pill: cow.pill, side: edge)).fittingSize
    }

    private func setFrame(_ frame: NSRect?) {
        guard let frame else {
            spot = nil
            content.mode = .expanded
            panel.setFrame(FloatingCowLayout.defaultFrame(), display: true)
            return
        }
        panel.setFrame(frame, display: true)
    }

    // MARK: 拖动与悬停

    /// 拖动总在展开的样子下进行；从贴边状态拖出时先展开。
    private func dragStarted() -> NSPoint {
        if case .collapsed = content.mode {
            content.mode = .expanded
            applyFrame()
        }
        mouseLeftAt = nil
        return panel.frame.origin
    }

    /// 松手：碰到屏幕左右边缘就贴边收起，否则停在这里；都记下来。
    private func dragEnded() {
        let next = FloatingCowLayout.spot(afterDragging: panel.frame)
        spot = next
        next.save()
        if case .docked(let edge, _, _) = next {
            content.mode = .collapsed(edge)
        }
        applyFrame()
        updateHoverTimer()
    }

    /// 只在贴边时轮询鼠标：移到探头上展开，离开展开的小牛一会儿后收回。
    private func updateHoverTimer() {
        let needed: Bool
        if case .docked = spot, panel.isVisible { needed = true } else { needed = false }
        guard needed != (hoverTimer != nil) else { return }
        hoverTimer?.invalidate()
        hoverTimer = nil
        guard needed else { return }
        let timer = Timer(timeInterval: Self.hoverInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func checkHover() {
        guard case .docked = spot, !eventView.isDragging else { return }
        let mouse = NSEvent.mouseLocation
        switch content.mode {
        case .collapsed:
            if panel.frame.contains(mouse) {
                content.mode = .expanded
                mouseLeftAt = nil
                applyFrame()
            }
        case .expanded:
            if FloatingCowLayout.figureRect(in: panel.frame).contains(mouse) {
                mouseLeftAt = nil
            } else if let left = mouseLeftAt {
                if Date().timeIntervalSince(left) >= Self.collapseDelay, case .docked(let edge, _, _) = spot {
                    content.mode = .collapsed(edge)
                    mouseLeftAt = nil
                    applyFrame()
                }
            } else {
                mouseLeftAt = Date()
            }
        }
    }

    // MARK: 右键菜单

    /// 原生菜单，跟随系统深浅色 (ADR-0004)。
    private func showMenu(for event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        menu.addItem(item("今天先藏起来", #selector(MenuTarget.hideForToday)))
        menu.addItem(item("改发薪日…", #selector(MenuTarget.changePayday)))
        menu.addItem(.separator())
        menu.addItem(item("关掉悬浮小牛", #selector(MenuTarget.turnOff)))
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private lazy var menuTarget = MenuTarget(controller: self)

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = menuTarget
        return item
    }

    /// 菜单项的 target 要是 NSObject。
    @MainActor
    private final class MenuTarget: NSObject {
        private weak var controller: FloatingCowController?

        init(controller: FloatingCowController) {
            self.controller = controller
        }

        @objc func hideForToday() {
            controller?.send(.hideFloatingCowForToday)
        }

        @objc func changePayday() {
            controller?.actions.openSettings()
        }

        @objc func turnOff() {
            controller?.send(.setShowsFloatingCow(false))
        }
    }

    private func send(_ command: Command) {
        do {
            try model.send(command)
        } catch {
            // 这两条命令没有校验，正常不会被拒绝。
            logger.error("悬浮小牛命令失败：\(error.message, privacy: .public)")
        }
        actions.stateChanged()
    }

    // MARK: 窗口

    private func makePanel() -> FloatingCowPanel {
        let panel = FloatingCowPanel()
        eventView.onClick = { [weak self] in self?.actions.openTodayPanel() }
        eventView.onDragStart = { [weak self] in self?.dragStarted() ?? .zero }
        eventView.onDragEnd = { [weak self] in self?.dragEnded() }
        eventView.onRightClick = { [weak self] event, view in self?.showMenu(for: event, in: view) }
        panel.contentView = eventView
        return panel
    }
}
