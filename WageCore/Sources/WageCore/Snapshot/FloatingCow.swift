import Foundation

/// 桌面悬浮小牛 (issue #21 起，现为整个 App 的形象) 的展示内容：小牛姿势、头顶气泡、脚边存钱罐、贴边收起时的小条。
/// 全部由场景 (`CowScene`) 推导，外壳原样展示；拿到 nil (见 `Snapshot.floatingCow`) 时收起浮窗。
/// 倒计时类的气泡精确到分钟，内容一分钟才变一次，外壳每次刷新比较后才重画。
public struct FloatingCow: Sendable, Equatable {
    public let scene: CowScene
    public var pose: FloatingCowPose { scene.pose }
    public let bubble: FloatingCowBubble
    /// 休息日 (不赚钱也不在发薪档) 没有罐子，为 nil。
    public let jar: CoinJar?
    /// 拖到屏幕左右边缘收起后，探头旁边的白色小条。
    public let pill: FloatingCowPill
}

/// 小牛此刻的场景，决定姿势、气泡、罐子。
/// 判定顺序：白干计时中 > 发薪当天 > 上班中且距发薪 1 至 3 天 > 日状态 (全天请假按休息日)。
/// 发薪临近只顶替上班中，干饭、下班、休息照常。
public enum CowScene: Sendable, Equatable {
    /// 未上班。
    case beforeWork
    /// 上班中。
    case working
    /// 干饭中。
    case lunch
    /// 请假中：落在两段上班中间的请假。
    case onLeave
    /// 已下班。
    case offWork
    /// 休息日，也用于全天请假。
    case restDay
    /// 白干计时中，不论日状态。
    case unpaidWork
    /// 上班中、距发薪 1 至 3 天。
    case paydaySoon(days: Int)
    /// 发薪当天，整天都是。
    case payday

    init(today: Today) {
        let paydayDays = today.paydayCountdown?.days
        if today.unpaidWork.isRunning {
            self = .unpaidWork
        } else if paydayDays == 0 {
            self = .payday
        } else if today.status == .working, let days = paydayDays, (1...3).contains(days) {
            self = .paydaySoon(days: days)
        } else {
            self = switch today.status {
            case .restDay: .restDay
            case .notStarted: .beforeWork
            case .working: .working
            case .lunchBreak: .lunch
            case .onLeave: .onLeave
            case .offWork: .offWork
            }
        }
    }

    public var pose: FloatingCowPose {
        switch self {
        case .beforeWork: .yawning
        case .working: .working
        case .lunch: .eating
        case .onLeave, .restDay: .sunbathing
        case .offWork: .lyingFlat
        case .unpaidWork: .sweating
        case .paydaySoon: .excited
        case .payday: .paid
        }
    }

    var style: FloatingCowStyle {
        switch self {
        case .offWork, .restDay: .ink
        case .beforeWork, .working, .lunch, .onLeave, .unpaidWork, .paydaySoon: .accent
        case .payday: .payday
        }
    }
}

/// 悬浮小牛的全身姿势，外壳对应到 `Assets.xcassets/FloatingCow` 里的素材与动作。
public enum FloatingCowPose: Sendable, Equatable, CaseIterable {
    /// 打哈欠：未上班。
    case yawning
    /// 打工：端着咖啡，半睁眼。
    case working
    /// 捧碗干饭。
    case eating
    /// 躺平：已下班。
    case lyingFlat
    /// 戴墨镜晒太阳：休息日、请假。
    case sunbathing
    /// 抱着电脑冒汗：白干。
    case sweating
    /// 兴奋握拳：快发薪。
    case excited
    /// 跳起来撒金币：发薪当天。
    case paid
}

/// 气泡与小条的配色。
public enum FloatingCowStyle: Sendable, Equatable {
    /// 白底，数字 ink。
    case ink
    /// 白底，数字 accent。
    case accent
    /// 发薪当天：气泡 money 绿底白字、周围撒金币彩带；小条仍是白底，字用 money 绿。
    case payday
}

/// 小牛头顶的气泡：小字前缀 + 大字 (可带单位) + 一句台词。
public struct FloatingCowBubble: Sendable, Equatable {
    /// 小字前缀，如「距下班」「今天」。
    public let prefix: String
    /// 大字，如「2:14」「¥952.38」「2」「明天」「发工资啦」。
    public let value: String
    /// 大字后面的小单位「天」，没有时为 nil。
    public let unit: String?
    /// 大字是数字 (用等宽数字字体) 还是文字 (明天、发工资啦，用正文字体)。
    public let numeric: Bool
    /// 今天的台词，同一天不变。
    public let quip: String
    public let style: FloatingCowStyle
}

/// 贴边收起时的白色小条：上行大字 (如「8 天」「明天」)，下行小字说明 (如「距发薪」「发薪」)。
public struct FloatingCowPill: Sendable, Equatable {
    public let value: String
    public let caption: String
    public let style: FloatingCowStyle

    public init(value: String, caption: String, style: FloatingCowStyle) {
        self.value = value
        self.caption = caption
        self.style = style
    }
}

/// 小牛脚边的玻璃存钱罐：罐内硬币层数 = 发薪周期进度，上一个发薪日空罐，发薪当天装满并在罐口冒出几枚。
public struct CoinJar: Sendable, Equatable {
    /// 罐子最多装几层硬币 (设计稿 3、2、3、2、3 枚交错排)。
    public static let maxRows = 5

    /// 0 至 `maxRows`。
    public let rows: Int
    /// 发薪当天：装满之后罐口再冒出几枚。
    public let overflowing: Bool

    public init(rows: Int, overflowing: Bool) {
        self.rows = rows
        self.overflowing = overflowing
    }

    /// 进度 0 至 1 换算成层数，四舍五入 (72% 约 4 层)。
    init(progress: Decimal, overflowing: Bool = false) {
        let value = NSDecimalNumber(decimal: progress).doubleValue * Double(Self.maxRows)
        self.init(rows: min(Self.maxRows, max(0, Int(value.rounded()))), overflowing: overflowing)
    }
}

extension FloatingCow {
    /// 开关关着或今天藏起来了时为 nil。
    init?(today: Today, settings: InterfaceSettings, now: Moment) {
        guard settings.showsFloatingCow, settings.floatingCowHiddenOn != today.date else { return nil }
        let scene = CowScene(today: today)
        self.scene = scene
        bubble = FloatingCowBubble(scene: scene, today: today, now: now)
        jar = CoinJar(scene: scene, today: today)
        pill = FloatingCowPill(scene: scene, bubble: bubble)
    }
}

extension FloatingCowBubble {
    init(scene: CowScene, today: Today, now: Moment) {
        let quip = scene.quip(on: today.date)
        let plan = today.plan
        switch scene {
        case .beforeWork:
            self.init(countdown: "距上班", to: plan?.start, now: now, quip: quip, style: scene.style)
        case .working, .onLeave:
            self.init(countdown: "距下班", to: plan?.end, now: now, quip: quip, style: scene.style)
        case .lunch:
            self.init(countdown: "距开工", to: plan?.lunch?.end, now: now, quip: quip, style: scene.style)
        case .offWork:
            let earned = today.earnings.map { Format.money($0.cap) } ?? "-"
            self.init(prefix: "今天赚了", value: earned, unit: nil, numeric: true, quip: quip, style: scene.style)
        case .restDay:
            let days = today.nextAttendanceDay.map { $0.days(since: today.date) }
            self.init(days: days, prefix: "距上班", quip: quip, style: scene.style)
        case .unpaidWork:
            let milliseconds = today.unpaidWork.running?.milliseconds ?? 0
            let value = Format.hoursMinutes(seconds: milliseconds / 1000)
            self.init(prefix: "已白干", value: value, unit: nil, numeric: true, quip: quip, style: scene.style)
        case .paydaySoon(let days):
            self.init(days: days, prefix: "距发薪", quip: quip, style: scene.style)
        case .payday:
            self.init(prefix: "今天", value: "发工资啦", unit: nil, numeric: false, quip: quip, style: scene.style)
        }
    }

    /// 倒计时到 `end` (时:分，不足一分钟进位，不会显示 0:00)；没有 `end` 时显示「-」。
    private init(countdown prefix: String, to end: Date?, now: Moment, quip: String, style: FloatingCowStyle) {
        let value = end.map { end in
            let seconds = max(0, end.timeIntervalSince(now.date))
            return Format.hoursMinutes(seconds: Int((seconds / 60).rounded(.up)) * 60)
        }
        self.init(prefix: prefix, value: value ?? "-", unit: nil, numeric: value != nil, quip: quip, style: style)
    }

    /// 还有几天：1 天写「明天」，没有 (一年内不上班) 时写「-」。
    private init(days: Int?, prefix: String, quip: String, style: FloatingCowStyle) {
        switch days {
        case 1: self.init(prefix: prefix, value: "明天", unit: nil, numeric: false, quip: quip, style: style)
        case let days?: self.init(prefix: prefix, value: "\(days)", unit: "天", numeric: true, quip: quip, style: style)
        case nil: self.init(prefix: prefix, value: "-", unit: nil, numeric: false, quip: quip, style: style)
        }
    }
}

private extension CoinJar {
    /// 发薪那两档装发薪周期进度 (当天装满冒出来)，休息日没有罐子，其余装今天的工作进度。
    init?(scene: CowScene, today: Today) {
        switch scene {
        case .payday, .paydaySoon:
            guard let countdown = today.paydayCountdown else { return nil }
            self.init(progress: countdown.progress, overflowing: scene == .payday)
        case .restDay:
            return nil
        case .beforeWork, .working, .lunch, .onLeave, .offWork, .unpaidWork:
            guard let earnings = today.earnings else { return nil }
            self.init(progress: earnings.progress)
        }
    }
}

private extension FloatingCowPill {
    /// 小条照抄气泡：上行大字 (带单位)，下行前缀；发薪当天、明天发薪写作「今天 / 发薪」「明天 / 发薪」。
    init(scene: CowScene, bubble: FloatingCowBubble) {
        switch scene {
        case .payday: self.init(value: "今天", caption: "发薪", style: bubble.style)
        case .paydaySoon(days: 1): self.init(value: "明天", caption: "发薪", style: bubble.style)
        default:
            let value = bubble.unit.map { "\(bubble.value) \($0)" } ?? bubble.value
            self.init(value: value, caption: bubble.prefix, style: bubble.style)
        }
    }
}
