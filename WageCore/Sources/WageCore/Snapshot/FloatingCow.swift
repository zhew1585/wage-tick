import Foundation

/// 桌面悬浮小牛 (issue #21，设计稿方案 C) 的展示内容：小牛姿势、头顶气泡、脚边存钱罐、贴边收起时的小条。
/// 全部由距发薪推导，外壳原样展示；拿到 nil (见 `Snapshot.floatingCow`) 时收起浮窗。
public struct FloatingCow: Sendable, Equatable {
    public let mood: PaydayMood
    public var pose: FloatingCowPose { mood.pose }
    public let bubble: FloatingCowBubble
    public let jar: CoinJar
    /// 拖到屏幕左右边缘收起后，探头旁边的白色小条。
    public let pill: FloatingCowPill
}

/// 心情档位，按距发薪天数分 (issue #21 表)。
/// 判定顺序：当天 > 明天 > 快了 > 一周左右 > 刚发完 > 还早。
/// 刚发完 (上一个实际发薪日后 1 至 3 天) 只会和还早重叠 (发薪周期至少二十几天)，重叠时算刚发完；
/// 周期极短、和更近的档位重叠时，以倒数更近的档位为准。
public enum PaydayMood: Sendable, Equatable, CaseIterable {
    /// 还早：> 14 天。
    case farOff
    /// 一周左右：4 至 14 天。
    case withinTwoWeeks
    /// 快了：2 至 3 天。
    case soon
    /// 明天：1 天。
    case tomorrow
    /// 当天：0 天。
    case payday
    /// 刚发完：上一个实际发薪日之后 1 至 3 天。
    case justPaid

    init(_ countdown: PaydayCountdown) {
        let sincePrevious = countdown.next.days(since: countdown.previous) - countdown.days
        switch countdown.days {
        case 0: self = .payday
        case 1: self = .tomorrow
        case 2...3: self = .soon
        case 4...14: self = .withinTwoWeeks
        default: self = (1...3).contains(sincePrevious) ? .justPaid : .farOff
        }
    }

    public var pose: FloatingCowPose {
        switch self {
        case .farOff, .withinTwoWeeks, .justPaid: .working
        case .soon, .tomorrow: .excited
        case .payday: .paid
        }
    }
}

/// 悬浮小牛的三种全身姿势 (设计稿 Cow Character 组件)，外壳对应到 `Assets.xcassets` 里的透明 PNG。
public enum FloatingCowPose: Sendable, Equatable {
    /// 打工：端着咖啡，半睁眼。
    case working
    /// 兴奋：握拳。
    case excited
    /// 发薪：跳起来撒金币。
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
    /// 小字前缀，如「距发薪」「今天」。
    public let prefix: String
    /// 大字，如「8」「明天」「发工资啦」。
    public let value: String
    /// 大字后面的小单位「天」；大字是文字 (明天、发工资啦) 时为 nil，外壳据此决定大字用数字字体还是正文字体。
    public let unit: String?
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
    /// 没设发薪日、开关关着或今天藏起来了时为 nil。
    init?(today: Today, settings: InterfaceSettings) {
        guard settings.showsFloatingCow, settings.floatingCowHiddenOn != today.date,
              let countdown = today.paydayCountdown else { return nil }
        let mood = PaydayMood(countdown)
        self.mood = mood
        bubble = FloatingCowBubble(countdown: countdown, mood: mood, quip: mood.quip(for: countdown, on: today.date))
        jar = CoinJar(progress: countdown.progress, overflowing: mood == .payday)
        pill = FloatingCowPill(countdown: countdown, style: mood.style)
    }
}

extension PaydayMood {
    var style: FloatingCowStyle {
        switch self {
        case .farOff, .justPaid: .ink
        case .withinTwoWeeks, .soon, .tomorrow: .accent
        case .payday: .payday
        }
    }
}

private extension FloatingCowBubble {
    init(countdown: PaydayCountdown, mood: PaydayMood, quip: String) {
        self.quip = quip
        style = mood.style
        switch mood {
        case .payday:
            (prefix, value, unit) = ("今天", "发工资啦", nil)
        case .tomorrow:
            (prefix, value, unit) = ("距发薪", "明天", nil)
        case .farOff, .withinTwoWeeks, .soon, .justPaid:
            (prefix, value, unit) = ("距发薪", "\(countdown.days)", "天")
        }
    }
}

private extension FloatingCowPill {
    init(countdown: PaydayCountdown, style: FloatingCowStyle) {
        switch countdown.days {
        case 0: self.init(value: "今天", caption: "发薪", style: style)
        case 1: self.init(value: "明天", caption: "发薪", style: style)
        default: self.init(value: "\(countdown.days) 天", caption: "距发薪", style: style)
        }
    }
}
