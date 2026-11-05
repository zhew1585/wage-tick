import Foundation

// 请假命令 (PRD 4.4.2、F6)：今天来自面板，过去和未来的日子来自历史编辑 (PRD 4.6.1)。

/// 给 `date` 设置请假，过去、今天、未来都可以。`mergingWithExisting` 为 true 时 (新请一条) 与已有的另一半天假合并为全天，
/// 为 false 时 (编辑) 整条替换。这天不应出勤 (按节假日表与单日覆盖判定) 或比例越界时拒绝 (PRD 4.3.5 #8、#22)。
func setLeave(
    _ leave: Leave, mergingWithExisting: Bool, on date: LocalDate, state: AppState, holidays: HolidayTable
) throws(CommandError) -> AppState {
    guard state.profile != nil else { throw .notOnboarded }
    guard AttendanceRule(holidays: holidays).isAttendanceDay(date) else { throw .notAttendanceDay }
    if let error = Validation.leaveDeductionPercent(leave.deductionPercent) { throw error }
    var record = state.dayRecord(on: date) ?? DayRecord(date: date)
    record.leave = mergingWithExisting ? leave.merged(into: record.leave) : leave
    return state.replacingDayRecord(record)
}

/// 撤销 `date` 的请假；没有请假时原样返回。日记录因此变空时一并删掉。
/// 不看这天是否应出勤：变成不上班日的那天，已有的请假要能撤掉 (#14 遗留)。
func cancelLeave(on date: LocalDate, state: AppState) -> AppState {
    guard var record = state.dayRecord(on: date), record.leave != nil else { return state }
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
