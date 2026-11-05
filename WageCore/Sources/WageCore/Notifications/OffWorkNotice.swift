import Foundation

// 下班通知 (PRD 4.6.3、F13)：「推进到此刻」跨过当日计划下班时产生一次下班事件。
// 休息日 (含全天请假，按休息日呈现【D2】) 不产生；同一天只产生一次，重启、睡眠恢复后也不重复。

/// 今天的下班事件走到哪一步，随状态存盘。
/// 只有先看到过今天还没下班 (`announced == false`)，之后再看到已下班，才算"跨过"计划下班。
/// 这样晚上才开机或才完成引导时不会补发；昨天没跨完的也不会挪到今天发。
struct OffWorkWatch: Sendable, Equatable, Codable {
    let day: LocalDate
    /// 今天的下班事件已处理过 (发了，或者通知关着而略过)。
    let announced: Bool
}

/// 通知相关的固定文案，外壳原样展示。
public enum NotificationCopy {
    /// 系统拒绝通知权限时设置页的提示 (AC-SET-05，PRD 4.3.5 #15)。
    public static let permissionDenied = "通知被关了，去系统设置里打开"

    /// 下班通知正文 (PRD 4.6.3)：老板路过模式下不含金额 (AC-BOSS-03)。
    /// 结算按滚动区域以外的格式截掉末尾 0，如「1000」「952.381」。
    static func offWork(settlement: Decimal, bossMode: Bool) -> String {
        bossMode ? "今天的砖搬完了，可以走了" : "今日 \(Format.trimmed(settlement)) 元已到账，可以走了"
    }
}

/// 推进到此刻里的下班部分。日状态取自快照，与菜单栏、面板看到的完全一致。
/// - 今天还没下班 (未上班、上班中、午休中)：记下"今天在等下班"，当天已处理过的不动。
/// - 今天已下班且之前在等：产生下班事件 (通知开着时)，记为已处理。
/// 关着通知时也记为已处理，之后再打开不补发今天的。
func advanceOffWork(_ state: AppState, now: Moment, holidays: HolidayTable) -> (state: AppState, events: [DomainEvent]) {
    guard let today = snapshot(of: state, at: now, holidays: holidays).today else { return (state, []) }
    switch today.status {
    case .notStarted, .working, .lunchBreak:
        guard state.offWorkWatch?.day != today.date else { return (state, []) }
        return (state.watchingOffWork(OffWorkWatch(day: today.date, announced: false)), [])
    case .offWork:
        guard state.offWorkWatch == OffWorkWatch(day: today.date, announced: false), let earnings = today.earnings else {
            return (state, [])
        }
        let next = state.watchingOffWork(OffWorkWatch(day: today.date, announced: true))
        guard state.settings.offWorkNotification else { return (next, []) }
        let message = NotificationCopy.offWork(settlement: earnings.cap, bossMode: state.settings.bossMode)
        return (next, [.offWork(message: message)])
    case .restDay:
        return (state, [])
    }
}

/// 下班通知开关属于界面设置，引导前也能改。
func setOffWorkNotification(_ enabled: Bool, state: AppState) -> AppState {
    var next = state
    next.settings.offWorkNotification = enabled
    return next
}

private extension AppState {
    func watchingOffWork(_ watch: OffWorkWatch) -> AppState {
        var next = self
        next.offWorkWatch = watch
        return next
    }
}
