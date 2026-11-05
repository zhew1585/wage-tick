import Foundation

/// 金额展示格式 (PRD 4.7.1 第 5 条，D9)。计算全程保留完整精度，只在这里取舍。
enum Format {
    /// 滚动区域 (菜单栏数字、面板主数字)：四舍五入到 4 位，永远显示 4 位小数，不带货币符号。
    static func rolling(_ amount: Decimal) -> String {
        let text = NSDecimalNumber(decimal: round(amount, scale: 4)).stringValue
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return "\(parts[0]).\(fraction.padding(toLength: 4, withPad: "0", startingAt: 0))"
    }

    /// 滚动区域以外的数字：四舍五入到 4 位后截掉末尾的 0，整数不显示小数点，如 `1000`、`952.381`。
    static func trimmed(_ amount: Decimal) -> String {
        trimmingZeros(round(amount, scale: 4))
    }

    /// 面板里滚动区域以外的金额：带 ¥，按 `trimmed` 取舍，如 `¥1000`。
    static func money(_ amount: Decimal) -> String {
        "¥" + trimmed(amount)
    }

    /// 日期，如「2月16日 周一」；不在 `reference` 同一年时带年份，如「2027年1月4日 周一」。
    static func date(_ date: LocalDate, relativeTo reference: LocalDate) -> String {
        let year = date.year == reference.year ? "" : "\(date.year)年"
        return "\(year)\(date.month)月\(date.day)日 \(weekdayNames[date.weekday - 1])"
    }

    /// 此刻在所在时区的时分，如「15:07」。
    static func time(_ now: Moment) -> String {
        let parts = now.calendar.dateComponents([.hour, .minute], from: now.date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 下班倒计时 h:mm:ss，如 `3:00:00`。不足一秒的部分向上取整，到点前不会提前显示 `0:00:00`。
    static func countdown(from now: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        let minutes = String(format: "%02d", seconds / 60 % 60)
        let rest = String(format: "%02d", seconds % 60)
        return "\(seconds / 3600):\(minutes):\(rest)"
    }

    /// 工作进度百分比：四舍五入到 2 位后截掉末尾的 0，如 `57.14%`、`12.5%`、`0%`。
    static func percent(_ ratio: Decimal) -> String {
        trimmingZeros(round(ratio * 100, scale: 2)) + "%"
    }

    /// 毫秒换算成小时，保留完整精度，交给 `trimmed` 取舍。
    static func hours(milliseconds: Int) -> Decimal {
        Decimal(milliseconds) / 3_600_000
    }

    private static func trimmingZeros(_ value: Decimal) -> String {
        let text = NSDecimalNumber(decimal: value).stringValue
        guard text.contains(".") else { return text }
        let trimmed = text.replacing(/0+$/, with: "")
        return trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
    }

    /// 四舍五入 (half up) 到 `scale` 位小数。
    static func round(_ amount: Decimal, scale: Int) -> Decimal {
        var input = amount
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }
}
