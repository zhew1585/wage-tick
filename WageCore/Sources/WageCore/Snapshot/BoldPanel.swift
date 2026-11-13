import Foundation

/// 大胆版首页头图大数字下面的一行说明 (设计稿「大胆风格」)：每个状态一句，前面一个图标。
public struct HeroCaption: Sendable, Equatable {
    /// 图标的意思，外壳对应到具体图标。
    public enum Icon: Sendable, Equatable {
        /// 钱在涨：上班中。
        case rising
        /// 闹钟：未上班、休息日 (几点开工)。
        case alarm
        /// 暂停：干饭中。
        case pause
        /// 请假中。
        case leave
        /// 月亮：已下班。
        case moon
        /// 钱在往外倒：白干中。
        case falling
    }

    public let icon: Icon
    public let text: String
}

extension HeroCaption {
    /// 未上班「10:00 开工」，上班中「每秒 +¥0.0397 · 时薪 ¥142.86」，干饭中「13:00 继续计钱」，
    /// 请假中「16:00 回来继续」，已下班同面板小字 (「准点下班，赢」或今日白干汇总)，
    /// 白干中「18:00 起白干 · 每秒倒贴 ¥0.0397」，休息日「周一 10:00 开工」(明天上班写「明天」)。
    init(today: Today, now: Moment) {
        if let running = today.unpaidWork.running {
            let start = Format.time(Moment(date: running.since, timeZone: now.timeZone))
            let day = running.date == today.date ? "" : "\(Format.shortDay(running.date, relativeTo: today.date)) "
            let rate = today.schedule.owed(dailyWage: today.dailyWage, milliseconds: 1000)
            self.init(icon: .falling, text: "\(day)\(start) 起白干 · 每秒倒贴 \(Format.rollingMoney(rate))")
            return
        }
        guard let plan = today.plan, let earnings = today.earnings else {
            self.init(icon: .alarm, text: Self.nextStart(today: today, timeZone: now.timeZone))
            return
        }
        let time = { (date: Date) in Format.time(Moment(date: date, timeZone: now.timeZone)) }
        switch today.status {
        case .notStarted:
            self.init(icon: .alarm, text: "\(time(plan.start)) 开工")
        case .lunchBreak:
            self.init(icon: .pause, text: "\(time(plan.lunch?.end ?? plan.end)) 继续计钱")
        case .onLeave:
            self.init(icon: .leave, text: "\(time(plan.leave?.end ?? plan.end)) 回来继续")
        case .offWork:
            self.init(icon: .moon, text: today.unpaidWork.offWorkCaption)
        case .working, .restDay:
            let hourly = today.schedule.owed(dailyWage: today.dailyWage, milliseconds: 3_600_000)
            self.init(icon: .rising, text: "每秒 +\(Format.rollingMoney(earnings.perSecond)) · 时薪 \(Format.money(hourly))")
        }
    }

    /// 休息日：下个上班日几点开工；一年内都不上班时写「今天不计钱」。
    private static func nextStart(today: Today, timeZone: TimeZone) -> String {
        guard let next = today.nextAttendanceDay else { return "今天不计钱" }
        let start = String(format: "%02d:%02d", today.schedule.start.hour, today.schedule.start.minute)
        let day = next.days(since: today.date) == 1 ? "明天" : Format.weekday(next)
        return "\(day) \(start) 开工"
    }
}

extension TodayPanel {
    /// 大胆版头图标题 (设计稿「大胆风格」)：按小牛场景一句话。
    /// 上班中「今天又给自己挣了」(上班日发薪「发薪日照样搬砖」)、未上班与休息日「离开工还有」(明天上班「明天就要上班」)、
    /// 干饭中「干饭不计钱，先停一下」、请假中「请假中，钱先不涨」、已下班「今天的砖搬完了」、
    /// 白干中「下班了还在倒贴」(休息日「休息日被迫营业」，跨过零点后沿用快照标签，如「昨天已倒贴」)、
    /// 发薪日赶上休息日「这个月挣了」。
    static func heroKicker(today: Today, scene: CowScene, body: Body) -> String {
        switch body {
        case .unpaidWork(let unpaidWork):
            guard unpaidWork.label == "今日已倒贴" else { return unpaidWork.label }
            return today.status == .restDay ? "休息日被迫营业" : "下班了还在倒贴"
        case .rest:
            if scene == .payday { return "这个月挣了" }
            return today.nextAttendanceDay.map { $0.days(since: today.date) == 1 } == true ? "明天就要上班" : "离开工还有"
        case .attendance:
            return switch scene {
            case .beforeWork: "离开工还有"
            case .lunch: "干饭不计钱，先停一下"
            case .onLeave: "请假中，钱先不涨"
            case .offWork: "今天的砖搬完了"
            case .payday: "发薪日照样搬砖"
            default: "今天又给自己挣了"
            }
        }
    }

    /// 大胆版统计行 (设计稿「大胆风格」)：倒计时已在小牛气泡里，统计行不再放距离下班。
    /// 应出勤日未下班为 [今日扣款, 本月累计, 距发薪]，已下班为 [今日结算, 本月累计, 距发薪]；
    /// 白干中 (当天开始、应出勤日) 为 [今日结算, 今日扣款, 本月累计]；休息日为 [本月累计, 本月已上班, 距发薪]。
    /// 没设发薪日时第三项换成距离周末 (一年内没有休息日时不放)。金额取整到元、带千分位。
    static func boldStats(today: Today, body: Body) -> [StatItem] {
        let month = StatItem(title: "本月累计", value: Format.groupedMoney(today.monthToDate))
        let third = today.paydayCountdown.map(StatItem.boldPayday) ?? today.restCountdown.map(StatItem.restCountdown)
        let deduction = today.settlement.map { StatItem.todayDeduction($0.deductionTotal) }
        switch body {
        case .attendance:
            let first = today.status == .offWork
                ? today.earnings.map { StatItem(title: "今日结算", value: Format.groupedMoney($0.cap)) }
                : deduction
            return [first, month, third].compactMap { $0 }
        case .unpaidWork:
            guard let earnings = today.earnings, let deduction else {
                return [StatItem(title: "今日结算", value: Format.groupedMoney(0)), month, third].compactMap { $0 }
            }
            return [StatItem(title: "今日结算", value: Format.groupedMoney(earnings.cap)), deduction, month]
        case .rest(let rest):
            let attended = rest.stats.first { $0.title == "本月已上班" }
            return [month, attended, third].compactMap { $0 }
        }
    }
}

extension StatItem {
    /// 距发薪：当天写「今天」，其余「11 天」。
    static func boldPayday(_ countdown: PaydayCountdown) -> StatItem {
        StatItem(title: "距发薪", value: countdown.days == 0 ? "今天" : "\(countdown.days) 天")
    }

    /// 今日扣款：没扣为「¥0」，扣了为「−¥50」(外壳按开头的「−」用亏钱色)。
    static func todayDeduction(_ total: Decimal) -> StatItem {
        StatItem(title: "今日扣款", value: total > 0 ? "−" + Format.groupedMoney(total) : Format.groupedMoney(0))
    }
}

extension Format {
    /// 统计行里的金额：取整到元 (四舍五入)、带千分位，如「¥3,521」「¥0」。
    static func groupedMoney(_ amount: Decimal) -> String {
        let yuan = NSDecimalNumber(decimal: round(amount, scale: 0)).intValue
        let digits = String(abs(yuan))
        var grouped = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        return (yuan < 0 ? "−¥" : "¥") + grouped
    }
}
