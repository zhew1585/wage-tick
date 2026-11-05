import Foundation

/// 白干计时中的面板内容 (PRD F4)，我还没走与被迫营业相同。
public struct UnpaidWorkPanel: Sendable, Equatable {
    /// 主数字，带 ¥，4 位小数：今日已倒贴，持续滚动。
    public let headline: String
    /// 如「18:00 起 · 已白干 1:05:12 · 每秒 +0.0397」。
    public let caption: String
    /// 统计行：今日结算、本月累计，与已下班相同。
    public let stats: [StatItem]

    public init(headline: String, caption: String, stats: [StatItem]) {
        self.headline = headline
        self.caption = caption
        self.stats = stats
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
    init(today: Today, now: Moment) {
        let unpaidWork = today.unpaidWork
        let start = Format.time(Moment(date: unpaidWork.runningSince ?? now.date, timeZone: now.timeZone))
        headline = Format.rollingMoney(unpaidWork.owed)
        caption = "\(start) 起 · 已白干 \(Format.elapsed(milliseconds: unpaidWork.milliseconds)) · 每秒 +\(Format.trimmed(unpaidWork.perSecond))"
        // 被迫营业的休息日没有收入，今日结算为 0 (AC-OT-04)。
        stats = today.earnings.map { AttendancePanel.offWorkStats(today: today, earnings: $0) } ?? [
            StatItem(title: "今日结算", value: Format.money(0)),
            StatItem(title: "本月累计", value: Format.money(today.monthToDate)),
        ]
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
