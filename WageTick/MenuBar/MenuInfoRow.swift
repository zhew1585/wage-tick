import AppKit
import WageCore

/// 菜单栏菜单最上面的一行今日信息 (issue #18，设计稿「菜单栏菜单 · 加今日信息」)：左边名称、右边数值。
/// 用菜单项的自定义视图画，不可点、悬停不高亮。名称和数值都用系统的 secondaryLabel 色，跟随深浅色，不用 accent 色：
/// 原生菜单里深色文字表示能点，灰色表示只看，整行灰色才不会被当成入口；数值靠等宽数字与 medium 字重保持好读。
/// 文字原样取自快照的 `menuInfo`。
final class MenuInfoRow: NSView {
    /// 和原生菜单项文字对齐的左右边距。
    private static let inset: CGFloat = 14
    private static let size = NSSize(width: 240, height: 22)

    private let titleField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        autoresizingMask = .width
        titleField.font = .menuFont(ofSize: 0)
        titleField.textColor = .secondaryLabelColor
        valueField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        valueField.textColor = .secondaryLabelColor
        valueField.alignment = .right
        for field in [titleField, valueField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.leadingAnchor.constraint(greaterThanOrEqualTo: titleField.trailingAnchor, constant: Self.inset),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(_ item: StatItem) {
        titleField.stringValue = item.title
        valueField.stringValue = item.value
    }
}
