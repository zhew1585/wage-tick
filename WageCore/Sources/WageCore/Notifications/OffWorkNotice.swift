import Foundation

// 下班通知 (PRD 4.6.3、F13)：「推进到此刻」跨过当日计划下班时产生一次下班事件。
// 休息日 (含全天请假，按休息日呈现【D2】) 不产生；同一天只产生一次，重启、睡眠恢复后也不重复。

/// 今天的下班事件走到哪一步，随状态存盘。
/// 只有先看到过今天还没下班 (`handled == false`)，之后再看到已下班，才算"跨过"计划下班。
/// 这样晚上才开机或才完成引导时不会补发；昨天没跨完的也不会挪到今天发。
struct OffWorkWatch: Sendable, Equatable, Codable {
    let day: LocalDate
    /// 今天的下班事件已处理过 (发了，或者通知关着而略过)。
    let handled: Bool
}

/// 推进到此刻的第 3 步 (见 `advance`)。日状态与结算取自 `Today`，与菜单栏、面板看到的完全一致。
/// - 今天还没下班 (未上班、上班中、干饭中、请假中)：记下"今天在等下班"，当天已处理过的不动。
/// - 今天已下班且之前在等：产生下班事件 (通知开着时)，记为已处理。
/// 关着通知时也记为已处理，之后再打开不补发今天的。
func advanceOffWork(_ state: AppState, now: Moment, holidays: HolidayTable) -> (state: AppState, events: [DomainEvent]) {
    guard let profile = state.profile else { return (state, []) }
    let today = Today(profile: profile, dayRecords: state.dayRecords, now: now, holidays: holidays)
    switch today.status {
    case .notStarted, .working, .lunchBreak, .onLeave:
        guard state.offWorkWatch?.day != today.date else { return (state, []) }
        return (state.watchingOffWork(OffWorkWatch(day: today.date, handled: false)), [])
    case .offWork:
        guard state.offWorkWatch == OffWorkWatch(day: today.date, handled: false), let settlement = today.settlement else {
            return (state, [])
        }
        let next = state.watchingOffWork(OffWorkWatch(day: today.date, handled: true))
        guard state.settings.offWorkNotification else { return (next, []) }
        // 当日结算 = 今日上限 (含扣钱与请假扣薪，PRD 4.3.4)。
        let message = NotificationCopy.offWork(settlement: settlement.cap)
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
