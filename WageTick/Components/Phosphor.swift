import SwiftUI

/// 设计稿用的 Phosphor 图标 (Regular 字重，MIT 许可，见 `Resources/Icons/Phosphor-LICENSE.txt`)。
/// SVG 放在 `Assets.xcassets/Phosphor/`，按模板图渲染，颜色跟随 `foregroundStyle`。
/// 设计稿 (Pencil) 用的是 1.x 的图形 (如 flag-banner 是左边竖杆)，所以取自 `@phosphor-icons/core@1.4.9`，不是 2.x。
/// 新增图标：把该版本 `assets/regular/<名字>.svg` 拷进同名 imageset (svg 标签补上 width/height 256)，再在这里加一个 case。
///
/// 用法：`PhosphorIcon(.flagBanner, size: 13).foregroundStyle(Palette.accent)`；
/// 放进按钮 `Label` 的 icon 里时不用给尺寸，按钮样式会把它框成 14pt。
enum Phosphor: String {
    case arrowClockwise = "arrow-clockwise"
    case arrowRight = "arrow-right"
    case briefcase
    case calendarBlank = "calendar-blank"
    case caretDown = "caret-down"
    case caretLeft = "caret-left"
    case caretRight = "caret-right"
    case caretUp = "caret-up"
    case check
    case clock
    case downloadSimple = "download-simple"
    case flagBanner = "flag-banner"
    case gearSix = "gear-six"
    case hourglassSimple = "hourglass-simple"
    case pencilSimple = "pencil-simple"
    case personSimpleRun = "person-simple-run"
    case pushPin = "push-pin"
    case pushPinFill = "push-pin-fill"
    case trash
    case trendDown = "trend-down"
    case umbrella
    case warning
    // 目标、历史、设置 (760 设计稿) 用到的。
    case bellSlash = "bell-slash"
    case checkCircle = "check-circle"
    // 发薪日 (issue #20)：概览页脚「今天发薪」。
    case coins
    case drop
    case list
    case plus
    case swap
    case x
    // 悬浮小牛发薪当天撒的金币彩带 (设计稿用 Bold 字重)。
    case coinBold = "coin-bold"
    case coinsBold = "coins-bold"
    case confettiBold = "confetti-bold"
    case sparkleBold = "sparkle-bold"
    case starFourBold = "star-four-bold"
    // 大胆版扣钱表单：原因方块 (迟到、早退、其他) 与头图里的余额行。
    case alarm
    case door
    case dotsThree = "dots-three"
    case wallet

    var image: Image {
        Image("Phosphor/\(rawValue)").renderingMode(.template)
    }
}

/// 一个方形的 Phosphor 图标；不给 `size` 时撑满外面给的框。
/// 也可直接传资源目录里的模板图 (如 `.OnboardingIcon.arrowLeft`)，颜色同样跟随 `foregroundStyle`。
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

extension View {
    /// 图标和旁边的文字放进 `HStack(alignment: .firstTextBaseline)` 时用：图标底边落在文字基线下 1pt，
    /// 两者视觉上在同一水平线 (按中心对齐时 Noto Sans SC 的行框偏高，文字看起来比图标低)。
    func iconOnTextBaseline() -> some View {
        alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
    }
}
