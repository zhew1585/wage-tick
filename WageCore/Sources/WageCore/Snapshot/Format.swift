import Foundation

/// 金额展示格式 (PRD 4.7.1 第 5 条，D9)。计算全程保留完整精度，只在这里取舍。
enum Format {
    /// 滚动区域 (菜单栏数字、面板主数字)：四舍五入到 4 位，永远显示 4 位小数，不带货币符号。
    static func rolling(_ amount: Decimal) -> String {
        fixed(amount, scale: 4)
    }

    /// 桌面小组件主数字：四舍五入到 2 位，永远显示 2 位小数，不带货币符号，如 `571.43`、`0.00`、`1000.00`。
    /// 小组件约每分钟才刷新一次，4 位小数没有意义；固定 2 位让宽度不跳，与面板主数字永远带小数一个口径。
    static func cents(_ amount: Decimal) -> String {
        fixed(amount, scale: 2)
    }

    /// 四舍五入到 `scale` 位，并补足 `scale` 位小数。
    private static func fixed(_ value: Decimal, scale: Int) -> String {
        let text = NSDecimalNumber(decimal: round(value, scale: scale)).stringValue
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let fraction = parts.count > 1 ? String(parts[1]) : ""
        return "\(parts[0]).\(fraction.padding(toLength: scale, withPad: "0", startingAt: 0))"
    }

    /// 滚动区域以外的金额：四舍五入到 2 位；有小数时固定 2 位，整数不显示小数点，如 `1000`、`952.38`、`22.30`。
    static func amount(_ amount: Decimal) -> String {
        let rounded = round(amount, scale: 2)
        return rounded == round(rounded, scale: 0) ? trimmingZeros(rounded) : fixed(rounded, scale: 2)
    }

    /// 金额以外的计数 (如请假天数)：四舍五入到 2 位后截掉末尾的 0，如 `0.5`、`2`。
    static func trimmed(_ value: Decimal) -> String {
        trimmingZeros(round(value, scale: 2))
    }

    /// 可编辑输入框的预填值：保留到 4 位再截掉末尾的 0，免得没改就保存时把用户填的数四舍五入掉。
    static func editable(_ amount: Decimal) -> String {
        trimmingZeros(round(amount, scale: 4))
    }

    /// 面板主数字：带 ¥，按 `rolling` 固定 4 位小数，如 `¥571.4286`。
    static func rollingMoney(_ amount: Decimal) -> String {
        "¥" + rolling(amount)
    }

    /// 面板里滚动区域以外的金额：带 ¥，按 `amount` 取舍，如 `¥1000`、`¥952.38`。
    static func money(_ amount: Decimal) -> String {
        "¥" + self.amount(amount)
    }

    /// 日期，如「2月16日 周一」；不在 `reference` 同一年时带年份，如「2027年1月4日 周一」。
    static func date(_ date: LocalDate, relativeTo reference: LocalDate) -> String {
        let year = date.year == reference.year ? "" : "\(date.year)年"
        return "\(year)\(date.month)月\(date.day)日 \(weekday(date))"
    }

    /// 此刻在所在时区的时分，如「15:07」。
    static func time(_ now: Moment) -> String {
        let parts = now.calendar.dateComponents([.hour, .minute], from: now.date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }

    /// 此刻在所在时区的时分秒，如「15:07:30」(面板顶部时钟)。
    static func clock(_ now: Moment) -> String {
        let parts = now.calendar.dateComponents([.hour, .minute, .second], from: now.date)
        return String(format: "%02d:%02d:%02d", parts.hour!, parts.minute!, parts.second!)
    }

    static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 星期几，如「周五」。
    static func weekday(_ date: LocalDate) -> String {
        weekdayNames[date.weekday - 1]
    }

    /// 下班倒计时 h:mm:ss，如 `3:00:00`。不足一秒的部分向上取整，到点前不会提前显示 `0:00:00`。
    static func countdown(from now: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        let minutes = String(format: "%02d", seconds / 60 % 60)
        let rest = String(format: "%02d", seconds % 60)
        return "\(seconds / 3600):\(minutes):\(rest)"
    }

    /// 百分比 (`ratio` 为 0 至 1 的比例)：四舍五入到 2 位，永远显示 2 位小数，如 `57.14%`、`12.50%`、`0.00%`。
    /// 菜单栏进度模式也用它，滚动时宽度不跳。
    static func percent(_ ratio: Decimal) -> String {
        fixed(ratio * 100, scale: 2) + "%"
    }

    /// 工作进度里的小时数：保留 1 位小数并截掉末尾的 0，如 `7`、`5.1`。
    /// 已工作时长向下取 (`roundingDown: true`)，免得还没下班就显示成和应有时长一样。
    static func workHours(milliseconds: Int, roundingDown: Bool = false) -> String {
        var input = hours(milliseconds: milliseconds)
        var result = Decimal()
        NSDecimalRound(&result, &input, 1, roundingDown ? .down : .plain)
        return trimmingZeros(result)
    }

    /// 毫秒换算成小时，保留完整精度，交给调用方取舍。
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
