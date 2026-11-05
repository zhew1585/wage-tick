import Foundation

// 白干计时的命令 (PRD 4.4.3)。白干不改变日状态和任何收入，只记录白干段。

/// 开始一段白干，记在今天的日记录里。
/// 只在应出勤日的已下班、或休息日 (按节假日表判定，含全天请假) 可用，同一时间只能有一段 (规则 1、2)。
func startUnpaidWork(state: AppState, now: Moment, holidays: HolidayTable) throws(CommandError) -> AppState {
    let state = advanceUnpaidWork(state: state, now: now)
    guard let profile = state.profile else { throw .notOnboarded }
    guard state.runningUnpaidWork == nil else { throw .unpaidWorkAlreadyRunning }
    let today = Today(profile: profile, dayRecords: state.dayRecords, now: now, holidays: holidays)
    guard today.unpaidWork.canStart else { throw .unpaidWorkUnavailable }
    var record = state.dayRecord(on: today.date) ?? DayRecord(date: today.date)
    record.unpaidWork.append(UnpaidWorkSegment(start: now.date))
    return state.replacingDayRecord(record)
}

/// 停止计时中的那段白干，结束时刻为此刻。
func stopUnpaidWork(state: AppState, now: Moment) throws(CommandError) -> AppState {
    let state = advanceUnpaidWork(state: state, now: now)
    guard let running = state.runningUnpaidWork else { throw .unpaidWorkNotRunning }
    return state.updatingSegment(running) { segment in
        // 系统时间被拨回到开始之前时 (PRD 4.3.5 #11)，按零长度结束，不留下倒着的段。
        segment.end = max(now.date, segment.start)
    }
}

/// 推进到此刻：计时跨过当天 23:59:59 仍未停止的白干段，在 23:59:59 自动停止并标记疑似通宵 (规则 3，PRD 4.3.5 #12)。
/// 退出或睡眠期间不发命令，恢复后第一次推进时补做 (PRD 4.3.5 #13)。
func advanceUnpaidWork(state: AppState, now: Moment) -> AppState {
    guard let running = state.runningUnpaidWork else { return state }
    let cutoff = now.unpaidWorkCutoff(on: running.record.date)
    guard now.date >= cutoff else { return state }
    return state.updatingSegment(running) { segment in
        segment.end = max(cutoff, segment.start)
        segment.suspectedAllNighter = true
    }
}

/// 某段白干的位置：所在日记录与段的下标。
struct UnpaidWorkPosition {
    let record: DayRecord
    let index: Int
}

extension AppState {
    /// 计时中 (结束时刻为空) 的那段白干；同一时间最多一段。
    var runningUnpaidWork: UnpaidWorkPosition? {
        for record in dayRecords {
            if let index = record.unpaidWork.firstIndex(where: { $0.end == nil }) {
                return UnpaidWorkPosition(record: record, index: index)
            }
        }
        return nil
    }

    /// 返回改好了 `position` 那段之后的新状态。
    func updatingSegment(_ position: UnpaidWorkPosition, _ change: (inout UnpaidWorkSegment) -> Void) -> AppState {
        var record = position.record
        change(&record.unpaidWork[position.index])
        return replacingDayRecord(record)
    }
}
