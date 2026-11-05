import Foundation

/// 此刻：由外壳注入的时钟读数 (绝对时刻 + 系统当前时区)。
/// 核心内部从不读系统时间，所有"今天""现在几点"都从这里推导 (PRD 4.3.5 #11)。
public struct Moment: Sendable, Equatable {
    public let date: Date
    public let timeZone: TimeZone

    public init(date: Date, timeZone: TimeZone) {
        self.date = date
        self.timeZone = timeZone
    }

    /// 此刻所在时区的公历。
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// 此刻在所在时区的日期。
    var localDate: LocalDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// 此刻所在时区里，某天某个时刻对应的绝对时刻。
    func date(on day: LocalDate, at time: TimeOfDay) -> Date {
        calendar.date(from: DateComponents(
            year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute
        ))!
    }
}
