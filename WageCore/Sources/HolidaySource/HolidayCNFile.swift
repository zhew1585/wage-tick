import Foundation
import WageCore

/// 一个 holiday-cn 年份文件 (https://github.com/NateScarlet/holiday-cn，MIT) 解析后的内容。
/// 格式：`{"year": 2026, "days": [{"name": "国庆节", "date": "2026-10-01", "isOffDay": true}, …]}`，
/// `isOffDay` 为 true 是法定节假日，false 是调休上班日。
struct HolidayCNFile: Sendable {
    let year: Int
    /// 可能含相邻年份的日子 (如元旦假期跨年)，所以不按年份过滤。
    let days: [LocalDate: HolidayKind]

    /// 解析并校验。国务院发布前 holiday-cn 的文件存在但 `days` 为空，也当作没有数据。
    init(data: Data) throws(HolidayCNFileError) {
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw .unreadable(error.localizedDescription)
        }
        guard !raw.days.isEmpty else { throw .notPublished(raw.year) }
        var days: [LocalDate: HolidayKind] = [:]
        for day in raw.days {
            // 跨年假期最多涉及前后一年，更远的日期说明数据有问题，整份不用。
            guard let date = Self.parseDate(day.date), abs(date.year - raw.year) <= 1 else { throw .badDate(day.date) }
            days[date] = day.isOffDay ? .holiday : .makeupDay
        }
        year = raw.year
        self.days = days
    }

    /// `yyyy-MM-dd`，且必须是公历里真实存在的日子。
    private static func parseDate(_ text: String) -> LocalDate? {
        guard let match = text.wholeMatch(of: /(\d{4})-(\d{2})-(\d{2})/),
              let year = Int(match.1), let month = Int(match.2), let day = Int(match.3) else { return nil }
        let parts = DateComponents(calendar: gregorian, year: year, month: month, day: day)
        return parts.isValidDate ? LocalDate(year: year, month: month, day: day) : nil
    }

    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private struct Raw: Decodable {
        let year: Int
        let days: [Day]

        struct Day: Decodable {
            let date: String
            let isOffDay: Bool
        }
    }
}

enum HolidayCNFileError: Error, CustomStringConvertible {
    case unreadable(String)
    case notPublished(Int)
    case badDate(String)
    case wrongYear(expected: Int, actual: Int)

    var description: String {
        switch self {
        case .unreadable(let reason): "不是 holiday-cn 格式：\(reason)"
        case .notPublished(let year): "\(year) 年的放假安排还没发布"
        case .badDate(let text): "日期格式不对：\(text)"
        case .wrongYear(let expected, let actual): "要 \(expected) 年的数据，拿到的是 \(actual) 年"
        }
    }
}
