import AppKit
import SwiftUI

/// 悬浮小牛停在哪：随便放 (记展开浮窗的左下角)，或贴在某块屏幕的左右边缘 (记那条边的 x 与探头中心的高度)。
/// 存在 UserDefaults，跨启动保留；没存过时在主屏右下角、Dock 上方。
enum FloatingCowSpot: Codable, Equatable {
    case free(x: Double, y: Double)
    case docked(edge: FloatingCowEdge, edgeX: Double, midY: Double)

    private static let defaultsKey = "FloatingCow.Spot"

    static func load() -> FloatingCowSpot? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(FloatingCowSpot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// 一块屏幕的整块区域与可用区域 (去掉菜单栏、Dock)。几何计算只看这两样，方便脱离真实屏幕验证多屏布局。
struct FloatingCowDisplay: Equatable {
    let frame: NSRect
    let visibleFrame: NSRect

    /// 此刻接着的屏幕，第一块是主屏 (带菜单栏、坐标原点所在)。
    static var current: [FloatingCowDisplay] {
        NSScreen.screens.map { FloatingCowDisplay(frame: $0.frame, visibleFrame: $0.visibleFrame) }
    }
}

/// 浮窗位置的几何计算 (屏幕坐标，原点在主屏左下)。只算 frame，不碰窗口。
/// 多屏时 (各显示器独立空间) 一个窗口只画在一块屏上，横跨接缝的部分会被截掉，所以小牛本体总要整个落在一块屏里；
/// 贴边只贴桌面的真边缘，两块屏的接缝处不贴。
enum FloatingCowLayout {
    /// 默认位置里小牛离屏幕右边、Dock 上沿的距离。
    private static let defaultMargin = CGSize(width: 24, height: 8)
    /// 小牛身体离边缘不到这么远 (或已经拖出去一截) 时松手即贴边。
    private static let snapDistance: CGFloat = 12
    /// 贴边展开时小牛离边缘的距离。
    private static let dockedMargin: CGFloat = 8

    private static var insets: EdgeInsets { FloatingCowMetrics.figureInsets }
    private static var canvas: CGSize { FloatingCowMetrics.canvas }

    /// 主屏右下角、Dock 上方的展开浮窗。
    static func defaultFrame(displays: [FloatingCowDisplay] = FloatingCowDisplay.current) -> NSRect {
        let visible = displays.first?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: visible.maxX - defaultMargin.width + insets.trailing - canvas.width,
            y: visible.minY + defaultMargin.height - insets.bottom
        )
        return NSRect(origin: origin, size: canvas)
    }

    /// 停在 `spot` 时展开的浮窗；随便放的位置已不在任何屏幕上 (拔了外接屏) 时为 nil。
    /// 随便放的位置若因屏幕布局变化跨了接缝或出了可用区域，挪回所在屏幕里。
    static func expandedFrame(at spot: FloatingCowSpot, displays: [FloatingCowDisplay] = FloatingCowDisplay.current) -> NSRect? {
        switch spot {
        case .free(let x, let y):
            let frame = NSRect(origin: NSPoint(x: x, y: y), size: canvas)
            return display(for: frame, in: displays).map { fitted(frame, into: $0.visibleFrame) }
        case .docked(let edge, let edgeX, let midY):
            guard let visible = dockDisplay(edge: edge, edgeX: edgeX, midY: midY, in: displays)?.visibleFrame else { return nil }
            let x = edge == .right
                ? visible.maxX - dockedMargin + insets.trailing - canvas.width
                : visible.minX + dockedMargin - insets.leading
            let y = clamp(midY - canvas.height / 2, min: visible.minY, max: visible.maxY - canvas.height)
            return NSRect(x: x, y: y, width: canvas.width, height: canvas.height)
        }
    }

    /// 贴边收起的浮窗：贴边一侧与屏幕可用区域对齐，探头中心在 `midY`。
    static func collapsedFrame(
        edge: FloatingCowEdge, edgeX: Double, midY: Double, size: CGSize, displays: [FloatingCowDisplay] = FloatingCowDisplay.current
    ) -> NSRect? {
        guard let visible = dockDisplay(edge: edge, edgeX: edgeX, midY: midY, in: displays)?.visibleFrame else { return nil }
        let x = edge == .right ? visible.maxX - size.width : visible.minX
        let y = clamp(midY - size.height / 2, min: visible.minY, max: visible.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// 展开浮窗里小牛本体 (气泡、存钱罐、小牛) 大致占的区域：留白之内。
    static func figureRect(in frame: NSRect) -> NSRect {
        NSRect(
            x: frame.minX + insets.leading, y: frame.minY + insets.bottom,
            width: frame.width - insets.leading - insets.trailing, height: frame.height - insets.top - insets.bottom
        )
    }

    /// 拖完松手的位置该停哪：小牛身体碰到 (或越过) 所在屏幕可用区域的左右边缘、且那是桌面真边缘时贴边；
    /// 否则停在这，跨了接缝或出了可用区域的挪回小牛中心所在的屏幕里。
    static func spot(afterDragging frame: NSRect, displays: [FloatingCowDisplay] = FloatingCowDisplay.current) -> FloatingCowSpot {
        let figure = figureRect(in: frame)
        guard let display = display(for: frame, in: displays) else { return .free(x: frame.minX, y: frame.minY) }
        let visible = display.visibleFrame
        if figure.minX <= visible.minX + snapDistance, isOuterEdge(.left, of: display, atY: figure.midY, in: displays) {
            return .docked(edge: .left, edgeX: visible.minX, midY: figure.midY)
        }
        if figure.maxX >= visible.maxX - snapDistance, isOuterEdge(.right, of: display, atY: figure.midY, in: displays) {
            return .docked(edge: .right, edgeX: visible.maxX, midY: figure.midY)
        }
        let placed = fitted(frame, into: visible)
        return .free(x: placed.minX, y: placed.minY)
    }

    /// 小牛本体中心所在的屏幕，都不在时取和它相交最多的屏幕。
    private static func display(for frame: NSRect, in displays: [FloatingCowDisplay]) -> FloatingCowDisplay? {
        let figure = figureRect(in: frame)
        let center = NSPoint(x: figure.midX, y: figure.midY)
        if let display = displays.first(where: { $0.frame.contains(center) }) { return display }
        func overlap(_ display: FloatingCowDisplay) -> CGFloat {
            let shared = display.frame.intersection(figure)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        return displays.filter { overlap($0) > 0 }.max { overlap($0) < overlap($1) }
    }

    /// 平移浮窗，让小牛本体整个落在 `visible` 里 (透明留白可以出界)。
    private static func fitted(_ frame: NSRect, into visible: NSRect) -> NSRect {
        let figure = figureRect(in: frame)
        let x = clamp(figure.minX, min: visible.minX, max: visible.maxX - figure.width)
        let y = clamp(figure.minY, min: visible.minY, max: visible.maxY - figure.height)
        return frame.offsetBy(dx: x - figure.minX, dy: y - figure.minY)
    }

    /// `display` 的左 (右) 边在高度 `y` 处外面没有别的屏幕，即桌面的真边缘。
    /// 两块屏的接缝不算：贴在那里鼠标跨屏时会经过探头误展开，展开的浮窗也会被截掉。
    private static func isOuterEdge(
        _ edge: FloatingCowEdge, of display: FloatingCowDisplay, atY y: Double, in displays: [FloatingCowDisplay]
    ) -> Bool {
        let probe = NSPoint(x: edge == .right ? display.frame.maxX + 1 : display.frame.minX - 1, y: y)
        return !displays.contains { $0.frame.contains(probe) }
    }

    /// 贴边时用哪块屏幕：只在高度覆盖 `midY`、那条边是真边缘的屏幕里挑；那条边还在 (`edgeX` 对得上) 的优先，
    /// 屏幕布局变了时贴右边取最右的、贴左边取最左的。
    private static func dockDisplay(
        edge: FloatingCowEdge, edgeX: Double, midY: Double, in displays: [FloatingCowDisplay]
    ) -> FloatingCowDisplay? {
        let candidates = displays.filter { display in
            display.frame.minY <= midY && midY <= display.frame.maxY
                && isOuterEdge(edge, of: display, atY: midY, in: displays)
        }
        let sameEdge = candidates.first { display in
            abs((edge == .right ? display.visibleFrame.maxX : display.visibleFrame.minX) - edgeX) < 1
        }
        if let sameEdge { return sameEdge }
        return edge == .right
            ? candidates.max { $0.frame.maxX < $1.frame.maxX }
            : candidates.min { $0.frame.minX < $1.frame.minX }
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), Swift.max(lower, upper))
    }
}
