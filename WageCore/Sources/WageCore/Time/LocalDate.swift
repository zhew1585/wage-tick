import Foundation

/// 不带时区的公历日期，日记录、安装日期都用它标识。
public struct LocalDate: Sendable, Hashable, Comparable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var yearMonth: YearMonth { YearMonth(year: year, month: month) }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// 是否周六或周日。星期与时区无关，用 UTC 公历计算。
    var isWeekend: Bool {
        weekday == 1 || weekday == 7
    }

    /// 星期几：1 为周日，2 为周一，…，7 为周六 (公历 weekday 口径)。
    var weekday: Int {
        LocalDate.utcCalendar.component(.weekday, from: utcNoon)
    }

    /// 往后数 `days` 天的日期。
    func adding(days: Int) -> LocalDate {
        let date = LocalDate.utcCalendar.date(byAdding: .day, value: days, to: utcNoon)!
        let parts = LocalDate.utcCalendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    private var utcNoon: Date {
        LocalDate.utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

/// 年月，月薪按它记录。
public struct YearMonth: Sendable, Hashable, Comparable, Codable {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// 本月每一天。
    var days: [LocalDate] {
        let first = LocalDate.utcCalendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let count = LocalDate.utcCalendar.range(of: .day, in: .month, for: first)!.count
        return (1...count).map { LocalDate(year: year, month: month, day: $0) }
    }
}

/// 一天中的时刻，精确到分 (PRD 4.2.3)。
/// 取值 00:00 至 23:59，所以计划下班天然不会晚于 23:59 (PRD 4.3.5 #4)。
public struct TimeOfDay: Sendable, Hashable, Comparable, Codable {
    public let hour: Int
    public let minute: Int

    /// 越界的时分属于编程错误，直接中止。
    public init(hour: Int, minute: Int) {
        precondition(Self.isValid(hour: hour, minute: minute), "时刻越界：\(hour):\(minute)")
        self.hour = hour
        self.minute = minute
    }

    /// 从文件读入时不信任内容：越界的时分抛解码错误，不中止。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hour = try container.decode(Int.self, forKey: .hour)
        let minute = try container.decode(Int.self, forKey: .minute)
        guard Self.isValid(hour: hour, minute: minute) else {
            throw DecodingError.dataCorruptedError(forKey: .hour, in: container, debugDescription: "时刻越界：\(hour):\(minute)")
        }
        self.init(hour: hour, minute: minute)
    }

    private enum CodingKeys: String, CodingKey { case hour, minute }

    private static func isValid(hour: Int, minute: Int) -> Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}
