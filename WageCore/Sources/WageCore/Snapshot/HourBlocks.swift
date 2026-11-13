import Foundation

/// 大胆版首页的进度格 (设计稿「大胆风格」)：每格 1 小时，格数固定，不会越排越多。
/// - 应出勤日：格数是今天的有效工时 (四舍五入)，已过多少格按工作进度；已下班全满。
/// - 下班后白干：工时格全满，末尾多一格超时 (`overtime`)，右上角写白干时长。
/// - 休息日被迫营业：格数是一个标准工作日的工时，按白干时长填；超过一整天全满，长度不变，只靠右上角的时长。
/// 文字原样取自这里，外壳只排版。
public struct HourBlocks: Sendable, Equatable {
    /// 格数，至少 1。
    public let count: Int
    /// 已填多少格，可带小数 (当前这一小时填一部分)，0 至 `count`。
    public let filled: Double
    /// 工时格后面是否多一格超时 (下班后白干)。
    public let overtime: Bool
    /// 左上的说明，如「已搬砖 4 / 7 小时」「已白干 1:20 / 7 小时」。
    public let label: String
    /// 右上的大字，如「57%」「+1:05」。
    public let value: String
    /// 是否白干 (外壳用白干的红色)。
    public let isUnpaid: Bool
    /// 格子下面一行的左、中、右，如「10:00 上班」「12:00–13:00 干饭」「18:00 下班」；没有的为 nil。
    public let startText: String?
    public let middleText: String?
    public let endText: String?
}

extension HourBlocks {
    /// 应出勤日 (不在白干)：按工作进度填，已下班全满。百分比取整，如「57%」。
    init?(today: Today, now: Moment) {
        guard let plan = today.plan, let earnings = today.earnings else { return nil }
        let count = Self.count(milliseconds: plan.effectiveMilliseconds)
        let progress = NSDecimalNumber(decimal: earnings.progress).doubleValue
        let total = Format.workHours(milliseconds: plan.effectiveMilliseconds)
        let elapsedMilliseconds = plan.elapsedMilliseconds(at: now.date)
        let elapsed = elapsedMilliseconds >= plan.effectiveMilliseconds
            ? total
            : Format.workHours(milliseconds: elapsedMilliseconds, roundingDown: true)
        let ticks = Self.ticks(plan: plan, timeZone: now.timeZone)
        self.init(
            count: count, filled: min(Double(count), progress * Double(count)), overtime: false,
            label: "已搬砖 \(elapsed) / \(total) 小时", value: "\(Int((progress * 100).rounded(.down)))%", isUnpaid: false,
            startText: ticks.start, middleText: ticks.middle, endText: ticks.end
        )
    }

    /// 白干计时中：应出勤日工时格全满加一格超时；休息日按一个标准工作日的格数填白干时长。
    /// 下面一行：应出勤日为「10:00 上班」「18:00 下班」「19:05 现在」，休息日为「13:00 开始」「每格 1 小时」。
    init(today: Today, running: RunningUnpaidWork, now: Moment) {
        let elapsed = "+\(Format.hoursMinutes(seconds: running.milliseconds / 1000))"
        let time = { (date: Date) in Format.time(Moment(date: date, timeZone: now.timeZone)) }
        if let plan = today.plan, today.status != .restDay {
            let count = Self.count(milliseconds: plan.effectiveMilliseconds)
            let total = Format.workHours(milliseconds: plan.effectiveMilliseconds)
            self.init(
                count: count, filled: Double(count), overtime: true,
                label: "已搬砖 \(total) / \(total) 小时", value: elapsed, isUnpaid: true,
                startText: "\(time(plan.start)) 上班", middleText: "\(time(plan.end)) 下班", endText: "\(time(now.date)) 现在"
            )
        } else {
            let standard = today.schedule.standardMilliseconds
            let count = Self.count(milliseconds: standard)
            let hours = Double(running.milliseconds) / 3_600_000
            self.init(
                count: count, filled: min(Double(count), hours), overtime: false,
                label: "已白干 \(Format.hoursMinutes(seconds: running.milliseconds / 1000)) / \(Format.workHours(milliseconds: standard)) 小时",
                value: elapsed, isUnpaid: true,
                startText: "\(time(running.since)) 开始", middleText: nil, endText: "每格 1 小时"
            )
        }
    }

    /// 应出勤日格子下面一行：上班、饭点、下班时刻。
    private static func ticks(plan: DayPlan, timeZone: TimeZone) -> (start: String, middle: String?, end: String) {
        let time = { (date: Date) in Format.time(Moment(date: date, timeZone: timeZone)) }
        let lunch = plan.lunch.map { "\(time($0.start))–\(time($0.end)) 干饭" }
        return ("\(time(plan.start)) 上班", lunch, "\(time(plan.end)) 下班")
    }

    /// 休息日 (含全天请假，没在白干)：每个本月应出勤日一格，已过的填满，如「本月已搬砖 5 / 20 天」「25%」，下面写月初、月底。
    init(restMonthOf today: Today) {
        let total = max(1, today.monthAttendanceDays)
        let attended = min(today.attendedDays, total)
        let days = today.date.yearMonth.days
        self.init(
            count: total, filled: Double(attended), overtime: false,
            label: "本月已搬砖 \(attended) / \(total) 天", value: "\(attended * 100 / total)%", isUnpaid: false,
            startText: days.first.map(Format.monthDay), middleText: nil, endText: days.last.map(Format.monthDay)
        )
    }

    /// 工时换成格数：四舍五入到整小时，至少 1 格。
    private static func count(milliseconds: Int) -> Int {
        max(1, Int((Double(milliseconds) / 3_600_000).rounded()))
    }
}
