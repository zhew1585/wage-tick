import AppKit
import SwiftUI

/// 左键菜单的一行 (设计稿 F2 左键菜单)：左 15pt 图标、13 号文字，右侧 12 号快捷键；
/// 鼠标或方向键选中时为 accent 圆角底、白字。系统菜单的选中色跟随系统强调色，改不了，所以整行自绘。
///
/// 内容全部取自所在的 `NSMenuItem`：`image` (模板图)、`title`、`keyEquivalent` + 修饰键、`state` (开启时文字后打勾)。
/// 改了 item 的这些属性后调 `needsDisplay = true` 重绘。用法：`MenuRowView.attach(to: item)`。
/// 带视图的菜单项点击时系统不发 action，由 `mouseUp` 代发；快捷键仍按 item 的 `keyEquivalent` 由菜单处理。
final class MenuRowView: NSView {
    /// 菜单宽 220，行高 28 (上下内边距 5)；选中底左右各缩进 5，内容再缩进 9。
    private enum Metric {
        static let width: CGFloat = 220
        static let height: CGFloat = 28
        static let inset: CGFloat = 5
        static let padding: CGFloat = 9
        static let iconSize: CGFloat = 15
        static let checkSize: CGFloat = 13
        static let gap: CGFloat = 8
        static let checkGap: CGFloat = 6
        static let radius: CGFloat = 5
        static let keyOpacity: CGFloat = 0.8
    }

    private static let checkImage = NSImage(resource: .MenuIcon.check)
    /// 修饰键按系统惯例 ⌃⌥⇧⌘ 排在主键前。
    private static let modifierSymbols: [(NSEvent.ModifierFlags, String)] = [
        (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    /// 所在的菜单项。自己记着，不靠 `enclosingMenuItem`：后者只在视图挂进菜单窗口后才有。
    private weak var item: NSMenuItem?

    private init(item: NSMenuItem) {
        self.item = item
        super.init(frame: NSRect(x: 0, y: 0, width: Metric.width, height: Metric.height))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 给 `item` 换上自绘的行视图。
    static func attach(to item: NSMenuItem) {
        item.view = MenuRowView(item: item)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item else { return }
        // 关掉字体平滑的笔画加粗，字重与设计稿、SwiftUI 视图一致。
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        let highlighted = item.isHighlighted && item.isEnabled
        let row = bounds.insetBy(dx: Metric.inset, dy: 0)
        if highlighted {
            NSColor(Palette.accent).setFill()
            NSBezierPath(roundedRect: row, xRadius: Metric.radius, yRadius: Metric.radius).fill()
        }
        let foreground = highlighted ? NSColor(Palette.card) : NSColor(Palette.ink)
        let content = row.insetBy(dx: Metric.padding, dy: 0)

        if let image = item.image {
            drawTemplate(image, size: Metric.iconSize, at: content.minX, color: foreground)
        }
        let titleX = content.minX + Metric.iconSize + Metric.gap
        let titleFont = AppFont.nsFont(.ui, size: 13, weight: highlighted ? .medium : .regular)
        let titleWidth = drawText(item.title, font: titleFont, color: foreground, x: titleX)

        if item.state == .on {
            let color = highlighted ? foreground : NSColor(Palette.accent)
            drawTemplate(Self.checkImage, size: Metric.checkSize, at: titleX + titleWidth + Metric.checkGap, color: color)
        }

        let key = Self.keyText(for: item)
        if !key.isEmpty {
            let keyColor = highlighted ? foreground.withAlphaComponent(Metric.keyOpacity) : NSColor(Palette.muted)
            let keyFont = AppFont.nsFont(.ui, size: 12)
            let keyWidth = (key as NSString).size(withAttributes: [.font: keyFont]).width
            drawText(key, font: keyFont, color: keyColor, x: content.maxX - keyWidth)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let item, item.isEnabled, let menu = item.menu else { return }
        menu.cancelTracking()
        menu.performActionForItem(at: menu.index(of: item))
    }

    /// 快捷键文字，如「⌘1」「⌃⌥B」「⌘,」；没有快捷键时为空。
    static func keyText(for item: NSMenuItem) -> String {
        guard !item.keyEquivalent.isEmpty else { return "" }
        let mask = item.keyEquivalentModifierMask
        let modifiers = modifierSymbols.filter { mask.contains($0.0) }.map(\.1).joined()
        return modifiers + item.keyEquivalent.uppercased()
    }

    /// 垂直居中画一行文字，返回文字宽度。
    @discardableResult
    private func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: x, y: bounds.midY - size.height / 2), withAttributes: attributes)
        return size.width
    }

    /// 模板图按 `color` 上色，垂直居中画成 `size` 见方。
    private func drawTemplate(_ image: NSImage, size: CGFloat, at x: CGFloat, color: NSColor) {
        let rect = NSRect(x: x, y: bounds.midY - size / 2, width: size, height: size)
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            image.draw(in: bounds)
            color.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect)
    }
}

/// 左键菜单的分隔线 (设计稿：上下各 4、左右缩进 14，1pt，ink 10%)。不可选中。
final class MenuSeparatorView: NSView {
    private enum Metric {
        static let width: CGFloat = 220
        static let height: CGFloat = 9
        static let inset: CGFloat = 14
        static let opacity: CGFloat = 0.1
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Metric.width, height: Metric.height))
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(Palette.ink).withAlphaComponent(Metric.opacity).setFill()
        NSRect(x: Metric.inset, y: (bounds.height - 1) / 2, width: bounds.width - Metric.inset * 2, height: 1).fill()
    }

    /// 带分隔线视图的菜单项。
    static func item() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuSeparatorView()
        item.isEnabled = false
        return item
    }
}
