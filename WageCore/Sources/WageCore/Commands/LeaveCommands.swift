import Foundation

// 请假命令 (PRD 4.4.2、F6)：今天来自面板，过去和未来的日子来自历史编辑 (PRD 4.6.1)。

/// 给 `date` 设置请假，过去、今天、未来都可以；一天只有一条，已有时整条替换 (4.4.2 #4、#5)。
/// 这天不应出勤 (按节假日表与单日覆盖判定)、时段不合规 (见 `Validation.leaveRange`) 或比例越界时拒绝 (PRD 4.3.5 #8、#22)。
/// 时段按这天生效的作息校验。
func setLeave(
    _ leave: Leave, on date: LocalDate, state: AppState, holidays: HolidayTable
) throws(CommandError) -> AppState {
    guard let profile = state.profile else { throw .notOnboarded }
    guard AttendanceRule(holidays: holidays).isAttendanceDay(date) else { throw .notAttendanceDay }
    if let error = Validation.leaveRange(leave.range, schedule: profile.schedule(on: date)) { throw error }
    if let error = Validation.leaveDeductionPercent(leave.deductionPercent) { throw error }
    var record = state.dayRecord(on: date) ?? DayRecord(date: date)
    record.leave = leave
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

    /// 时间条的刻度 (分钟)：请假的开始、结束对齐到它。
    public static let leaveStepMinutes = 10
    /// 请假最短时长 (分钟)。
    public static let leaveMinimumMinutes = 10

    /// 请假时段 (PRD 4.4.2 #2)：落在计划上下班之内；开始、结束对齐到 10 分钟，或正好是计划上下班、饭点开始结束、
    /// 关闭饭点时的中点 (这样快捷的全天、前半天、后半天总能对上)；至少 10 分钟，计划本身更短时至少为整个计划。
    static func leaveRange(_ range: LeaveRange, schedule: WorkSchedule) -> CommandError? {
        let day = schedule.span
        let span = range.span
        guard span.length > 0, day.start <= span.start, span.end <= day.end else { return .leaveOutsideWorkHours }
        let anchors = schedule.leaveAnchors
        let onStep = { (minute: Int) in minute % leaveStepMinutes == 0 || anchors.contains(minute) }
        guard onStep(span.start), onStep(span.end) else { return .leaveOffStep }
        guard span.length >= min(leaveMinimumMinutes, day.length) else { return .leaveTooShort }
        return nil
    }
}

extension WorkSchedule {
    /// 不在 10 分钟刻度上也可以作为请假开始、结束的时刻：计划上下班、饭点开始结束 (或关闭饭点时的中点)。
    var leaveAnchors: Set<Int> {
        let boundary = halfDayBoundary
        return [span.start, span.end, boundary.start, boundary.end]
    }
}
