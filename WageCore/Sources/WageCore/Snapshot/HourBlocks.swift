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
    /// 左上的说明，如「已工作 4 / 7 小时」「已白干 1:20 / 7 小时」。
    public let label: String
    /// 右上的大字，如「57%」「+1:05」。
    public let value: String
    /// 是否白干 (外壳用白干的红色)。
    public let isUnpaid: Bool
}

extension HourBlocks {
    /// 应出勤日 (不在白干)：按工作进度填，已下班全满。
    init?(today: Today, now: Moment) {
        guard let plan = today.plan, let earnings = today.earnings else { return nil }
        let count = Self.count(milliseconds: plan.effectiveMilliseconds)
        let progress = NSDecimalNumber(decimal: earnings.progress).doubleValue
        let total = Format.workHours(milliseconds: plan.effectiveMilliseconds)
        let elapsedMilliseconds = plan.elapsedMilliseconds(at: now.date)
        let elapsed = elapsedMilliseconds >= plan.effectiveMilliseconds
            ? total
            : Format.workHours(milliseconds: elapsedMilliseconds, roundingDown: true)
        self.init(
            count: count, filled: min(Double(count), progress * Double(count)), overtime: false,
            label: "已工作 \(elapsed) / \(total) 小时", value: Format.percent(earnings.progress), isUnpaid: false
        )
    }

    /// 白干计时中：应出勤日工时格全满加一格超时；休息日按一个标准工作日的格数填白干时长。
    init(today: Today, running: RunningUnpaidWork) {
        let elapsed = "+\(Format.hoursMinutes(seconds: running.milliseconds / 1000))"
        if let plan = today.plan, today.status != .restDay {
            let count = Self.count(milliseconds: plan.effectiveMilliseconds)
            let total = Format.workHours(milliseconds: plan.effectiveMilliseconds)
            self.init(
                count: count, filled: Double(count), overtime: true,
                label: "已工作 \(total) / \(total) 小时", value: elapsed, isUnpaid: true
            )
        } else {
            let standard = today.schedule.standardMilliseconds
            let count = Self.count(milliseconds: standard)
            let hours = Double(running.milliseconds) / 3_600_000
            self.init(
                count: count, filled: min(Double(count), hours), overtime: false,
                label: "已白干 \(Format.hoursMinutes(seconds: running.milliseconds / 1000)) / \(Format.workHours(milliseconds: standard)) 小时",
                value: elapsed, isUnpaid: true
            )
        }
    }

    /// 工时换成格数：四舍五入到整小时，至少 1 格。
    private static func count(milliseconds: Int) -> Int {
        max(1, Int((Double(milliseconds) / 3_600_000).rounded()))
    }
}
