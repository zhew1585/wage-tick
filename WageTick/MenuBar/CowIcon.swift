import AppKit
import WageCore

/// 菜单栏小牛图标：程序绘制的牛头 + 右上角表示日状态的 SF Symbol 角标。
/// 模板图，自动适配浅色、深色菜单栏。正式美术与动画待设计稿。
@MainActor
enum CowIcon {
    private static let size = NSSize(width: 24, height: 18)
    private static var cache: [CowPose: NSImage] = [:]

    static func image(for pose: CowPose) -> NSImage {
        if let cached = cache[pose] { return cached }
        let badge = badgeSymbol(for: pose)
        let image = NSImage(size: size, flipped: false) { _ in
            drawHead()
            drawBadge(badge)
            return true
        }
        image.isTemplate = true
        cache[pose] = image
        return image
    }

    /// 每个日状态对应的角标 (PRD 4.3.3 主状态概览)。
    private static func badgeSymbol(for pose: CowPose) -> String {
        switch pose {
        case .sunbathing: "sun.max.fill"   // 晒太阳
        case .yawning: "sunrise.fill"      // 打哈欠
        case .grinding: "gearshape.fill"   // 埋头拉磨
        case .sleeping: "zzz"              // 趴着睡
        case .lyingFlat: "bed.double.fill" // 躺平
        }
    }

    /// 牛头：脸、两只角、两只耳朵，眼睛和鼻孔挖空。
    private static func drawHead() {
        NSColor.black.setFill()
        NSColor.black.setStroke()
        NSBezierPath(ovalIn: NSRect(x: 4, y: 1, width: 11, height: 11)).fill()
        NSBezierPath(ovalIn: NSRect(x: 0.5, y: 8, width: 4.5, height: 2.6)).fill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: 8, width: 4.5, height: 2.6)).fill()
        for (from, to) in [(NSPoint(x: 6.5, y: 11), NSPoint(x: 5, y: 15)), (NSPoint(x: 12.5, y: 11), NSPoint(x: 14, y: 15))] {
            let horn = NSBezierPath()
            horn.lineWidth = 1.6
            horn.lineCapStyle = .round
            horn.move(to: from)
            horn.line(to: to)
            horn.stroke()
        }
        NSGraphicsContext.current?.compositingOperation = .clear
        for rect in [
            NSRect(x: 6.6, y: 7, width: 1.8, height: 1.8), NSRect(x: 10.6, y: 7, width: 1.8, height: 1.8),
            NSRect(x: 7.2, y: 2.6, width: 1.5, height: 1.5), NSRect(x: 10.3, y: 2.6, width: 1.5, height: 1.5),
        ] {
            NSBezierPath(ovalIn: rect).fill()
        }
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }

    private static func drawBadge(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let origin = NSPoint(x: size.width - symbol.size.width, y: size.height - symbol.size.height)
        symbol.draw(in: NSRect(origin: origin, size: symbol.size))
    }
}
