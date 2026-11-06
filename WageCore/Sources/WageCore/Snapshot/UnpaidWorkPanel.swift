import Foundation

/// 白干计时中的面板内容 (PRD F4)，我还没走与被迫营业相同。
/// 跨过零点还在计时时，主数字与小字说的是开始那天，统计行、目标、情绪按钮照旧是今天的。
public struct UnpaidWorkPanel: Sendable, Equatable {
    /// 主数字上方的标签：当天开始为「今日已倒贴」，跨过零点后为「昨天已倒贴」(更早为「11月6日已倒贴」)。
    public let label: String
    /// 主数字，带 ¥，4 位小数：开始那天已倒贴，持续滚动。
    public let headline: String
    /// 如「18:00 起 · 已白干 1:05:12」，跨过零点后如「昨天 18:00 起 · 已白干 6:30:00」。时长是开始那天各段之和。
    public let caption: String
    /// 统计行：当天开始时为今日结算、今日扣款、本月累计，与已下班相同，休息日被迫营业没有今日扣款；
    /// 跨过零点后为今天平常的统计行 (如未上班的距离下班、今日扣款、本月累计，休息日的本月已上班、本月累计)。
    public let stats: [StatItem]
    /// 今天是否休息日 (含全天请假)：外壳据此决定情绪按钮行 (应出勤日仍有扣钱、请假)。
    public let isRestDay: Bool

    public init(label: String, headline: String, caption: String, stats: [StatItem], isRestDay: Bool) {
        self.label = label
        self.headline = headline
        self.caption = caption
        self.stats = stats
        self.isRestDay = isRestDay
    }
}

/// 白干计时按钮：文案与点下后要发的命令，外壳原样展示、原样发出。
public struct UnpaidWorkButton: Sendable, Equatable {
    public let title: String
    public let command: Command

    public init(title: String, command: Command) {
        self.title = title
        self.command = command
    }
}

extension UnpaidWorkPanel {
    /// `todayStats` 是今天不在计时时面板的统计行，跨过零点后用它。
    init(today: Today, running: RunningUnpaidWork, now: Moment, todayStats: [StatItem]) {
        let start = Format.time(Moment(date: running.since, timeZone: now.timeZone))
        let elapsed = "已白干 \(Format.elapsed(milliseconds: running.milliseconds))"
        isRestDay = today.status == .restDay
        headline = Format.rollingMoney(running.owed)
        guard running.date == today.date else {
            let day = Format.shortDay(running.date, relativeTo: today.date)
            label = "\(day)已倒贴"
            caption = "\(day) \(start) 起 · \(elapsed)"
            stats = todayStats
            return
        }
        label = "今日已倒贴"
        caption = "\(start) 起 · \(elapsed)"
        if let earnings = today.earnings, let settlement = today.settlement {
            // 应出勤日，含按休息日呈现的全天请假日：统计行与已下班相同，带今日结算与扣款。
            stats = AttendancePanel.offWorkStats(today: today, earnings: earnings, settlement: settlement)
        } else {
            // 不应出勤的休息日被迫营业：没有收入，今日结算为 0 (AC-OT-04)。
            stats = [
                StatItem(title: "今日结算", value: Format.money(0)),
                StatItem(title: "本月累计", value: Format.money(today.monthToDate)),
            ]
        }
    }
}

extension UnpaidWorkButton {
    /// 计时中为「终于下班了」；可以开始时，已下班为「我还没走」、休息日为「被迫营业」(规则 1)。
    init?(today: Today) {
        if today.unpaidWork.isRunning {
            self.init(title: "终于下班了", command: .stopUnpaidWork)
        } else if today.unpaidWork.canStart {
            self.init(title: today.status == .restDay ? "被迫营业" : "我还没走", command: .startUnpaidWork)
        } else {
            return nil
        }
    }
}

extension UnpaidWorkToday {
    /// 已下班主数字下方的小字：没有白干记录为「准点下班，赢」，有记录为「今日白干 h:mm · 倒贴 ¥x」(规则 6)。
    var offWorkCaption: String {
        guard hasRecords else { return "准点下班，赢" }
        return "今日白干 \(Format.hoursMinutes(milliseconds: milliseconds)) · 倒贴 \(Format.money(owed))"
    }
}

extension Format {
    /// 相对今天的短日期：前一天为「昨天」，更早为「11月6日」。
    static func shortDay(_ date: LocalDate, relativeTo today: LocalDate) -> String {
        date == today.adding(days: -1) ? "昨天" : monthDay(date)
    }

    /// 月日，如「11月6日」。
    static func monthDay(_ date: LocalDate) -> String {
        "\(date.month)月\(date.day)日"
    }

    /// 已过时长 h:mm:ss，不足一秒的部分舍去，如 `1:05:12`。
    static func elapsed(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds) / 1000
        return "\(seconds / 3600):\(String(format: "%02d", seconds / 60 % 60)):\(String(format: "%02d", seconds % 60))"
    }

    /// 时长 h:mm，不足一分钟的部分舍去，如 `1:30`。
    static func hoursMinutes(milliseconds: Int) -> String {
        let minutes = max(0, milliseconds) / 60_000
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }
}
