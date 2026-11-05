import SwiftUI

/// 设计稿用的 Phosphor 图标 (Regular 字重，MIT 许可，见 `Resources/Icons/Phosphor-LICENSE.txt`)。
/// SVG 放在 `Assets.xcassets/Phosphor/`，按模板图渲染，颜色跟随 `foregroundStyle`。
/// 设计稿 (Pencil) 用的是 1.x 的图形 (如 flag-banner 是左边竖杆)，所以取自 `@phosphor-icons/core@1.4.9`，不是 2.x。
/// 新增图标：把该版本 `assets/regular/<名字>.svg` 拷进同名 imageset (svg 标签补上 width/height 256)，再在这里加一个 case。
///
/// 用法：`PhosphorIcon(.flagBanner, size: 13).foregroundStyle(Palette.accent)`；
/// 放进按钮 `Label` 的 icon 里时不用给尺寸，按钮样式会把它框成 14pt。
enum Phosphor: String {
    case arrowRight = "arrow-right"
    case briefcase
    case calendarBlank = "calendar-blank"
    case caretDown = "caret-down"
    case caretLeft = "caret-left"
    case caretRight = "caret-right"
    case caretUp = "caret-up"
    case check
    case eyeSlash = "eye-slash"
    case flagBanner = "flag-banner"
    case gearSix = "gear-six"
    case hourglassSimple = "hourglass-simple"
    case pencilSimple = "pencil-simple"
    case personSimpleRun = "person-simple-run"
    case trash
    case trendDown = "trend-down"
    case umbrella
    case warning

    var image: Image {
        Image("Phosphor/\(rawValue)").renderingMode(.template)
    }
}

/// 一个方形的 Phosphor 图标；不给 `size` 时撑满外面给的框。
/// 也可直接传资源目录里的模板图 (如 `.OnboardingIcon.calculator`)，颜色同样跟随 `foregroundStyle`。
struct PhosphorIcon: View {
    private let image: Image
    var size: CGFloat?

    init(_ icon: Phosphor, size: CGFloat? = nil) {
        image = icon.image
        self.size = size
    }

    init(_ resource: ImageResource, size: CGFloat? = nil) {
        image = Image(resource).renderingMode(.template)
        self.size = size
    }

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
