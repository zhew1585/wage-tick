import SwiftUI
import WageCore

/// 今日概览的头图 (设计稿「首页 · 大胆版」与各状态)：按小牛场景取主色与姿势，文字与数字原样取自快照。
/// - 应出勤日：标题「今日已赚」(已下班「今日结算」)，大数字是今日已赚，小数位翻牌；干饭、请假、已下班时翻牌变灰不再跳。
///   未上班时大数字换成距上班的倒计时 (标题「离开工还有」)。
/// - 白干中：黑红头图，标题与大数字是已倒贴。
/// - 休息日：黄色头图，大数字是距上班几天；发薪日赶上休息日整页变绿，大数字换成本月累计。
/// 气泡：有倒计时的场景写倒计时 (如「距下班 3:00」)，其余写小牛今天的台词。上班日发薪只换小牛、撒彩纸，颜色不变。
struct PanelHomeHero: View {
    let panel: TodayPanel
    let collapse: CGFloat

    var body: some View {
        let theme = HeroTheme.forPanel(panel)
        let display = HeroDisplay(panel: panel)
        BoldHero(
            theme: theme,
            topLeading: "\(panel.dateText)  \(panel.timeText)",
            status: status,
            kicker: panel.heroKicker,
            caption: panel.heroCaption.text,
            captionIcon: Self.icon(panel.heroCaption.icon),
            cow: .pose(panel.cowScene.pose),
            bubble: bubble,
            confetti: panel.cowScene == .payday,
            collapse: collapse,
            compactValue: display.compact
        ) {
            HeroAmount(text: display.number, theme: theme, paused: display.paused, unit: display.unit, size: display.size)
        }
    }

    /// 说明行图标：钱在涨、闹钟、暂停、请假伞、月亮、钱往外倒。
    private static func icon(_ icon: HeroCaption.Icon) -> Phosphor {
        switch icon {
        case .rising: .trendUp
        case .alarm: .alarm
        case .sun: .sun
        case .pause: .pause
        case .leave: .umbrella
        case .moon: .moon
        case .falling: .trendDown
        }
    }

    private var status: HeroStatus {
        switch panel.body {
        case .unpaidWork: HeroStatus(label: panel.statusLabel, dot: .white, fill: Palette.hot)
        case .rest: HeroStatus(label: panel.statusLabel, dot: Palette.highlight)
        case .attendance:
            switch panel.cowScene {
            case .offWork: HeroStatus(label: panel.statusLabel, dot: Color(hex: 0x8CE99A))
            case .working, .paydaySoon, .payday: HeroStatus(label: panel.statusLabel, dot: Palette.lime)
            default: HeroStatus(label: panel.statusLabel, dot: Palette.highlight)
            }
        }
    }

    /// 未上班、已下班、休息日、发薪当天写快照里的短台词 (三到五个字)，其余写倒计时 (如「距下班 3:00」)。
    private var bubble: HeroBubbleContent {
        if let quip = panel.heroQuip {
            return HeroBubbleContent(value: quip, numeric: false)
        }
        let cow = panel.cowBubble
        let value = cow.unit.map { "\(cow.value) \($0)" } ?? cow.value
        return HeroBubbleContent(prefix: cow.prefix, value: value, numeric: cow.numeric)
    }
}

/// 头图里要排的大数字 (可带单位) 与窄栏里的小号数字。标题、说明行直接用快照的 `heroKicker`、`heroCaption`。
private struct HeroDisplay {
    var number: String
    var unit: String?
    var paused = false
    var size: CGFloat = 96
    var compact: String?

    init(panel: TodayPanel) {
        switch panel.body {
        case .attendance(let attendance):
            let scene = panel.cowScene
            if scene == .beforeWork {
                number = panel.cowBubble.value
                size = 84
                compact = number
                return
            }
            number = attendance.headline
            paused = scene == .lunch || scene == .onLeave || scene == .offWork
            // 已下班的数字定格成整数位多的结算额，缩小一点给躺平小牛的气泡让位置。
            if scene == .offWork { size = 80 }
            compact = HeroAmount.split(number).integer
        case .unpaidWork(let unpaidWork):
            number = unpaidWork.headline
            compact = HeroAmount.split(number).integer
        case .rest(let rest):
            if panel.cowScene == .payday, let month = rest.stats.first(where: { $0.title == "本月累计" }) {
                number = month.value
                size = 80
            } else {
                let cow = panel.cowBubble
                number = cow.value == "明天" ? "1" : cow.value
                unit = Int(number) == nil ? nil : "天"
                size = 120
            }
            compact = number
        }
    }
}
