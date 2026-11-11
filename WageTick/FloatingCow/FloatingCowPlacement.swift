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

/// 浮窗位置的几何计算 (屏幕坐标，原点在主屏左下)。只算 frame，不碰窗口。
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
    static func defaultFrame() -> NSRect {
        let visible = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: visible.maxX - defaultMargin.width + insets.trailing - canvas.width,
            y: visible.minY + defaultMargin.height - insets.bottom
        )
        return NSRect(origin: origin, size: canvas)
    }

    /// 停在 `spot` 时展开的浮窗；随便放的位置已不在任何屏幕上 (拔了外接屏) 时为 nil。
    static func expandedFrame(at spot: FloatingCowSpot) -> NSRect? {
        switch spot {
        case .free(let x, let y):
            let frame = NSRect(origin: NSPoint(x: x, y: y), size: canvas)
            return screen(for: frame) == nil ? nil : frame
        case .docked(let edge, let edgeX, let midY):
            guard let visible = dockScreen(edge: edge, edgeX: edgeX, midY: midY)?.visibleFrame else { return nil }
            let x = edge == .right
                ? visible.maxX - dockedMargin + insets.trailing - canvas.width
                : visible.minX + dockedMargin - insets.leading
            let y = clamp(midY - canvas.height / 2, min: visible.minY, max: visible.maxY - canvas.height)
            return NSRect(x: x, y: y, width: canvas.width, height: canvas.height)
        }
    }

    /// 贴边收起的浮窗：贴边一侧与屏幕可用区域对齐，探头中心在 `midY`。
    static func collapsedFrame(edge: FloatingCowEdge, edgeX: Double, midY: Double, size: CGSize) -> NSRect? {
        guard let visible = dockScreen(edge: edge, edgeX: edgeX, midY: midY)?.visibleFrame else { return nil }
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

    /// 拖完松手的位置该停哪：小牛身体碰到 (或越过) 所在屏幕可用区域的左右边缘时贴边，否则就停在这。
    static func spot(afterDragging frame: NSRect) -> FloatingCowSpot {
        let figure = figureRect(in: frame)
        guard let visible = screen(for: frame)?.visibleFrame else { return .free(x: frame.minX, y: frame.minY) }
        if figure.minX <= visible.minX + snapDistance {
            return .docked(edge: .left, edgeX: visible.minX, midY: figure.midY)
        }
        if figure.maxX >= visible.maxX - snapDistance {
            return .docked(edge: .right, edgeX: visible.maxX, midY: figure.midY)
        }
        return .free(x: frame.minX, y: frame.minY)
    }

    /// 小牛本体中心所在的屏幕，都不在时取和它相交最多的屏幕。
    static func screen(for frame: NSRect) -> NSScreen? {
        let figure = figureRect(in: frame)
        let center = NSPoint(x: figure.midX, y: figure.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return screen }
        func overlap(_ screen: NSScreen) -> CGFloat {
            let shared = screen.frame.intersection(figure)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        return NSScreen.screens.filter { overlap($0) > 0 }.max { overlap($0) < overlap($1) }
    }

    /// 贴边时用哪块屏幕：那条边还在 (`edgeX` 对得上) 的屏幕；屏幕布局变了时，在高度覆盖 `midY` 的屏幕里
    /// 贴右边取最右的、贴左边取最左的。
    private static func dockScreen(edge: FloatingCowEdge, edgeX: Double, midY: Double) -> NSScreen? {
        let candidates = NSScreen.screens.filter { $0.frame.minY <= midY && midY <= $0.frame.maxY }
        let sameEdge = candidates.first { screen in
            abs((edge == .right ? screen.visibleFrame.maxX : screen.visibleFrame.minX) - edgeX) < 1
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
