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
    /// 1970-01-01 是周四。
    var weekday: Int {
        ((dayNumber % 7 + 7 + 4) % 7) + 1
    }

    /// 往后数 `days` 天的日期。
    func adding(days: Int) -> LocalDate {
        LocalDate(dayNumber: dayNumber + days)
    }

    // 星期与加减天数用纯整数算法 (Howard Hinnant 的 days_from_civil / civil_from_days)，
    // 不经 Calendar：调用方会跨月甚至跨年逐日遍历，且每次刷新都要算，Calendar 太慢。

    /// 自 1970-01-01 起的天数。
    private var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        self.init(
            year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0),
            month: month,
            day: dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        )
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
