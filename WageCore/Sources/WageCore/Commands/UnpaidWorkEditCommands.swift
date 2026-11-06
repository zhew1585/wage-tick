import Foundation

// 历史里补记、修改、删除白干段 (PRD 4.4.3 #5、4.6.1)。只在过去和今天；白干不改变任何收入，休息日也能记 (被迫营业)。

/// 白干段表单里牛马填写的开始、结束时刻 (精确到分)，未经校验。
/// 开始在这一天；结束可以在之后的日子 (跨过零点)，最晚到这一天的自动停止时刻 (见 `UnpaidWorkClock.autoStop`)。
public struct UnpaidWorkInput: Sendable, Equatable {
    public let start: TimeOfDay
    public let end: TimeOfDay
    /// 结束在开始那天之后第几天：0 为当天，1 为次日。
    public let endDayOffset: Int

    public init(start: TimeOfDay, end: TimeOfDay, endDayOffset: Int = 0) {
        self.start = start
        self.end = end
        self.endDayOffset = endDayOffset
    }
}

/// 给 `date` 补记一段白干，按开始时刻排进当天各段。
func addUnpaidWork(
    _ input: UnpaidWorkInput, on date: LocalDate, state: AppState, now: Moment, holidays: HolidayTable
) throws(CommandError) -> AppState {
    guard date <= now.localDate else { throw .futureDate }
    let clock = try unpaidWorkClock(state: state, now: now, holidays: holidays)
    var record = state.dayRecord(on: date) ?? DayRecord(date: date)
    let segment = try validatedSegment(input, on: date, excluding: nil, state: state, clock: clock)
    record.unpaidWork = (record.unpaidWork + [segment]).sorted { $0.start < $1.start }
    return state.replacingDayRecord(record)
}

/// 修改 `date` 第 `index` 段白干。改过的段不再标可能忘了停：时段已由牛马确认。
/// 计时中的那段不能改 (要停就点「终于下班了」)。
func editUnpaidWork(
    index: Int, _ input: UnpaidWorkInput, on date: LocalDate, state: AppState, now: Moment, holidays: HolidayTable
) throws(CommandError) -> AppState {
    guard date <= now.localDate else { throw .futureDate }
    let clock = try unpaidWorkClock(state: state, now: now, holidays: holidays)
    guard var record = state.dayRecord(on: date), record.unpaidWork.indices.contains(index) else { throw .unpaidWorkNotFound }
    guard !clock.isRunning(record.unpaidWork[index], on: date) else { throw .unpaidWorkAlreadyRunning }
    let segment = try validatedSegment(input, on: date, excluding: index, state: state, clock: clock)
    var others = record.unpaidWork
    others.remove(at: index)
    record.unpaidWork = (others + [segment]).sorted { $0.start < $1.start }
    return state.replacingDayRecord(record)
}

/// 删除 `date` 第 `index` 段白干，计时中的也可以删 (相当于这次计时作废)；日记录因此变空时一并删掉。
func deleteUnpaidWork(index: Int, on date: LocalDate, state: AppState) throws(CommandError) -> AppState {
    guard var record = state.dayRecord(on: date), record.unpaidWork.indices.contains(index) else { throw .unpaidWorkNotFound }
    record.unpaidWork.remove(at: index)
    return state.replacingDayRecord(record)
}

private func unpaidWorkClock(state: AppState, now: Moment, holidays: HolidayTable) throws(CommandError) -> UnpaidWorkClock {
    guard let profile = state.profile else { throw .notOnboarded }
    return UnpaidWorkClock(profile: profile, holidays: holidays, dayRecords: state.dayRecords, now: now)
}

/// 校验并落到绝对时刻：结束晚于开始，不晚于此刻，不晚于这一天的自动停止时刻，
/// 且不与其他段重叠 (同一时间只能有一段，PRD 4.4.3 #2)。跨过零点的段可能与之后日子的段重叠，所以看所有日子。
/// `excluding` 是 `date` 这天正在修改的那段，不和自己比。计时中的段算到此刻，与推导时长同一口径。
private func validatedSegment(
    _ input: UnpaidWorkInput, on date: LocalDate, excluding: Int?, state: AppState, clock: UnpaidWorkClock
) throws(CommandError) -> UnpaidWorkSegment {
    let now = clock.now
    let start = now.date(on: date, at: input.start)
    let end = now.date(on: date.adding(days: input.endDayOffset), at: input.end)
    guard end > start else { throw .unpaidWorkEndNotAfterStart }
    guard end <= now.date else { throw .unpaidWorkInFuture }
    guard end <= clock.autoStop(after: date) else { throw .unpaidWorkBeyondAutoStop }
    let overlaps = state.dayRecords.contains { record in
        record.unpaidWork.enumerated().contains { index, other in
            guard !(record.date == date && index == excluding) else { return false }
            return start < clock.end(of: other, on: record.date) && other.start < end
        }
    }
    guard !overlaps else { throw .unpaidWorkOverlap }
    return UnpaidWorkSegment(start: start, end: end)
}
