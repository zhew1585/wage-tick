import Foundation

/// 距离周末 (PRD V1.13，GLOSSARY)：从今天到下一个休息日 (不应出勤的日子) 还有几天。
/// 按休息模式、法定节假日与调休判定 (`AttendanceRule`)，全天请假仍是应出勤日，照常倒数。
struct RestCountdown: Sendable, Equatable {
    /// 今天本身就是休息日时为 0。
    let days: Int
    /// 那个休息日是节假日表里的法定节假日 (不含单日覆盖)：叫「距离放假」，否则叫「距离周末」。
    let isHoliday: Bool
}

extension AttendanceRule {
    /// 从 `day` 起第一个休息日的倒数；一年内都没有时为 nil。
    func restCountdown(from day: LocalDate) -> RestCountdown? {
        (0...366).lazy
            .map { (days: $0, date: day.adding(days: $0)) }
            .first { !isAttendanceDay($0.date) }
            .map { RestCountdown(days: $0.days, isHoliday: isStatutoryHoliday($0.date)) }
    }

    /// 法定节假日：节假日表标为放假，且没有被单日覆盖改掉。
    private func isStatutoryHoliday(_ date: LocalDate) -> Bool {
        holidays.overrides[date] == nil && holidays.kind(on: date) == .holiday
    }
}

extension StatItem {
    /// 统计行里的距离周末：「距离周末 5 天」「距离放假 明天休息」「距离周末 正在休息」，醒目显示。
    static func restCountdown(_ countdown: RestCountdown) -> StatItem {
        let value = switch countdown.days {
        case 0: "正在休息"
        case 1: "明天休息"
        default: "\(countdown.days) 天"
        }
        return StatItem(title: countdown.isHoliday ? "距离放假" : "距离周末", value: value, isHighlighted: true)
    }
}
