import Foundation

/// 休息模式 (PRD 4.2.2)：每周哪几天不上班，节假日表、单日覆盖之外的兜底规则。一周从周一算起。
/// 存在 `Profile.restModes` 里，按月份记录，与月薪一样对整月生效。
public enum RestMode: Sendable, Equatable {
    /// 双休：周六、周日都休。
    case twoDaysOff
    /// 单休：只休周日，周六上班。
    case sundayOnly
    /// 大小周：大周周六日都休，小周只休周日，一周一换。
    /// `bigWeekMonday` 是某个大周的周一，往前往后每一周的大小都由它推出来 (相差偶数周为大周)。
    case alternating(bigWeekMonday: LocalDate)

    /// 按每周规律 `date` 是否休息 (不看节假日表与单日覆盖)。
    func isRestDay(_ date: LocalDate) -> Bool {
        restSource(on: date) != nil
    }

    /// 按每周规律 `date` 休息时的判定来源 (双休、单休、大周、小周)；要上班时为 nil。
    func restSource(on date: LocalDate) -> AttendanceSource? {
        let isSaturday = date.weekday == 7
        let isSunday = date.weekday == 1
        switch self {
        case .twoDaysOff:
            return isSaturday || isSunday ? .weekend : nil
        case .sundayOnly:
            return isSunday ? .sundayOnly : nil
        case .alternating:
            let big = isBigWeek(date)
            if isSunday { return big ? .bigWeek : .smallWeek }
            return isSaturday && big ? .bigWeek : nil
        }
    }

    /// 大小周里 `date` 所在的周是不是大周；不是大小周时为 false。
    func isBigWeek(_ date: LocalDate) -> Bool {
        guard case .alternating(let anchor) = self else { return false }
        let weeks = date.monday.days(since: anchor.monday) / 7
        return weeks % 2 == 0
    }

    /// 当前状态对应的选项：大小周按 `today` 所在的周是大周还是小周。
    func choice(on today: LocalDate) -> RestModeChoice {
        switch self {
        case .twoDaysOff: .twoDaysOff
        case .sundayOnly: .sundayOnly
        case .alternating: isBigWeek(today) ? .bigWeekNow : .smallWeekNow
        }
    }
}

/// 引导第 1 步「怎么休」、设置「休息模式」里的四个选项 (设计稿 P1 引导 · 1、P6 设置 · 760)。
/// 大小周拆成「这周休两天」「这周休一天」两项，选的那一刻就定下了每一周的大小。
public enum RestModeChoice: String, Sendable, Equatable, CaseIterable {
    case twoDaysOff
    case bigWeekNow
    case smallWeekNow
    case sundayOnly

    /// 选项标题，如「双休」「大小周」。
    public var title: String {
        switch self {
        case .twoDaysOff: "双休"
        case .bigWeekNow, .smallWeekNow: "大小周"
        case .sundayOnly: "单休"
        }
    }

    /// 选项下面的小字，如「周六日都休」「这周休两天」。
    public var subtitle: String {
        switch self {
        case .twoDaysOff: "周六日都休"
        case .bigWeekNow: "这周休两天"
        case .smallWeekNow: "这周休一天"
        case .sundayOnly: "只休周日"
        }
    }

    /// 设置页「休息模式」一行的值，如「双休」「大小周 · 这周休两天」。
    var summary: String {
        switch self {
        case .twoDaysOff, .sundayOnly: title
        case .bigWeekNow, .smallWeekNow: "\(title) · \(subtitle)"
        }
    }

    /// 在 `today` 选这一项得到的休息模式：大小周的锚点取这周 (大周) 或上周 (这周是小周) 的周一。
    func mode(on today: LocalDate) -> RestMode {
        switch self {
        case .twoDaysOff: .twoDaysOff
        case .sundayOnly: .sundayOnly
        case .bigWeekNow: .alternating(bigWeekMonday: today.monday)
        case .smallWeekNow: .alternating(bigWeekMonday: today.monday.adding(days: -7))
        }
    }
}

/// 某个月的休息模式，对该月整月生效。
public struct MonthlyRestMode: Sendable, Equatable, Codable {
    public let month: YearMonth
    public let mode: RestMode

    init(month: YearMonth, mode: RestMode) {
        self.month = month
        self.mode = mode
    }
}

extension RestMode: Codable {
    private enum Kind: String, Codable { case twoDaysOff, sundayOnly, alternating }
    private enum CodingKeys: String, CodingKey { case kind, bigWeekMonday }

    /// 从文件读入时大周锚点必须是周一，否则抛解码错误。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .twoDaysOff: self = .twoDaysOff
        case .sundayOnly: self = .sundayOnly
        case .alternating:
            let monday = try container.decode(LocalDate.self, forKey: .bigWeekMonday)
            guard monday.monday == monday else {
                throw DecodingError.dataCorruptedError(forKey: .bigWeekMonday, in: container, debugDescription: "大周锚点不是周一")
            }
            self = .alternating(bigWeekMonday: monday)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .twoDaysOff: try container.encode(Kind.twoDaysOff, forKey: .kind)
        case .sundayOnly: try container.encode(Kind.sundayOnly, forKey: .kind)
        case .alternating(let monday):
            try container.encode(Kind.alternating, forKey: .kind)
            try container.encode(monday, forKey: .bigWeekMonday)
        }
    }
}

extension LocalDate {
    /// 这天所在周的周一 (一周从周一算起)。
    var monday: LocalDate {
        adding(days: -((weekday + 5) % 7))
    }
}
