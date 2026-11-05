import Foundation

// 请假命令 (PRD 4.4.2、F6)。本票只覆盖今天，未来日期请假留给历史编辑票 (#15)。

/// 给今天设置请假。`mergingWithExisting` 为 true 时 (新请一条) 与已有的另一半天假合并为全天，
/// 为 false 时 (编辑) 整条替换。今天不应出勤 (按节假日表判定) 或比例越界时拒绝 (PRD 4.3.5 #8、#22)。
func setLeave(
    _ leave: Leave, mergingWithExisting: Bool, state: AppState, now: Moment, holidays: HolidayTable
) throws(CommandError) -> AppState {
    guard state.profile != nil else { throw .notOnboarded }
    let today = now.localDate
    guard AttendanceRule(holidays: holidays).isAttendanceDay(today) else { throw .notAttendanceDay }
    if let error = Validation.leaveDeductionPercent(leave.deductionPercent) { throw error }
    var record = state.dayRecord(on: today) ?? DayRecord(date: today)
    record.leave = mergingWithExisting ? leave.merged(into: record.leave) : leave
    return state.replacingDayRecord(record)
}

/// 撤销今天的请假；没有请假时原样返回。日记录因此变空时一并删掉。
func cancelLeave(state: AppState, now: Moment) -> AppState {
    guard var record = state.dayRecord(on: now.localDate), record.leave != nil else { return state }
    record.leave = nil
    return state.replacingDayRecord(record)
}

extension Validation {
    /// 请假扣薪比例必须在 0% 至 100% 之间，含两端；为空 (nil) 同样拦下 (PRD 4.3.5 #22)。
    /// 外壳的请假表单也直接调用，保证提示与命令一致。
    public static func leaveDeductionPercent(_ percent: Decimal?) -> CommandError? {
        guard let percent, (0...100).contains(percent) else { return .leavePercentOutOfRange }
        return nil
    }
}
