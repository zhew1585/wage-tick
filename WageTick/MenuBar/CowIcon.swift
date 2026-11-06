import AppKit
import WageCore

/// 菜单栏小牛图标 (设计稿 F2 菜单栏状态)：16pt 牛头 `CowGlyph` + 右上角 8pt 日状态角标 `CowBadge/*`。
/// 两者都是模板图 (牛脸白色部分已挖空)，合成后仍是模板图，自动适配浅色、深色菜单栏。
/// 角标位置照设计稿：牛头 18×16 框内 x=11、y=-2，向上探出 2pt，所以画布 19×18。
@MainActor
enum CowIcon {
    private static let size = NSSize(width: 19, height: 18)
    private static let glyphRect = NSRect(x: 0, y: 2, width: 16, height: 16)
    private static let badgeRect = NSRect(x: 11, y: 0, width: 8, height: 8)
    private static var cache: [CowPose: NSImage] = [:]

    static func image(for pose: CowPose) -> NSImage {
        if let cached = cache[pose] { return cached }
        let glyph = NSImage(resource: .cowGlyph)
        let badge = NSImage(named: "CowBadge/\(badgeName(for: pose))")
        // flipped：坐标与设计稿一致，左上角为原点。
        let image = NSImage(size: size, flipped: true) { _ in
            glyph.draw(in: glyphRect)
            badge?.draw(in: badgeRect)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "牛马鼓励器"
        cache[pose] = image
        return image
    }

    /// 每个日状态对应的角标 (设计稿 F2，Phosphor Bold 图标)。
    private static func badgeName(for pose: CowPose) -> String {
        switch pose {
        case .sunbathing: "sun"        // 晒太阳：休息日
        case .yawning: "moon"          // 打哈欠：未上班
        case .grinding: "lightning"    // 埋头拉磨：上班中
        case .sleeping: "bed"          // 趴着睡：干饭中
        case .lyingFlat: "armchair"    // 躺平：已下班
        case .sweating: "drop"         // 边拉磨边冒汗：白干计时中
        }
    }
}
