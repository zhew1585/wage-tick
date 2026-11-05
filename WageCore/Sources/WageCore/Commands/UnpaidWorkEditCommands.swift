import Foundation

// 历史里补记、修改、删除白干段 (PRD 4.4.3 #5、4.6.1)。只在过去和今天；白干不改变任何收入，休息日也能记 (被迫营业)。

/// 白干段表单里牛马填写的开始、结束时刻 (这一天之内，精确到分)，未经校验。
public struct UnpaidWorkInput: Sendable, Equatable {
    public let start: TimeOfDay
    public let end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }
}

/// 给 `date` 补记一段白干，按开始时刻排进当天各段。
func addUnpaidWork(_ input: UnpaidWorkInput, on date: LocalDate, state: AppState, now: Moment) throws(CommandError) -> AppState {
    guard date <= now.localDate else { throw .futureDate }
    var record = state.dayRecord(on: date) ?? DayRecord(date: date)
    let segment = try validatedSegment(input, on: date, others: record.unpaidWork, now: now)
    record.unpaidWork = (record.unpaidWork + [segment]).sorted { $0.start < $1.start }
    return state.replacingDayRecord(record)
}

/// 修改 `date` 第 `index` 段白干。改过的段不再标疑似通宵：时段已由牛马确认。
/// 计时中的那段不能改 (要停就点「终于下班了」)。
func editUnpaidWork(
    index: Int, _ input: UnpaidWorkInput, on date: LocalDate, state: AppState, now: Moment
) throws(CommandError) -> AppState {
    guard date <= now.localDate else { throw .futureDate }
    guard var record = state.dayRecord(on: date), record.unpaidWork.indices.contains(index) else { throw .unpaidWorkNotFound }
    guard !record.unpaidWork[index].isRunning(on: date, now: now) else { throw .unpaidWorkAlreadyRunning }
    var others = record.unpaidWork
    others.remove(at: index)
    let segment = try validatedSegment(input, on: date, others: others, now: now)
    record.unpaidWork = (others + [segment]).sorted { $0.start < $1.start }
    return state.replacingDayRecord(record)
}

/// 删除 `date` 第 `index` 段白干，计时中的也可以删 (相当于这次计时作废)；日记录因此变空时一并删掉。
func deleteUnpaidWork(index: Int, on date: LocalDate, state: AppState) throws(CommandError) -> AppState {
    guard var record = state.dayRecord(on: date), record.unpaidWork.indices.contains(index) else { throw .unpaidWorkNotFound }
    record.unpaidWork.remove(at: index)
    return state.replacingDayRecord(record)
}

/// 校验并落到绝对时刻：结束晚于开始，不晚于此刻，且不与当天其他段重叠 (同一时间只能有一段，PRD 4.4.3 #2)。
/// 计时中的段算到此刻 (最晚当天 23:59:59)，与推导时长同一口径。
private func validatedSegment(
    _ input: UnpaidWorkInput, on date: LocalDate, others: [UnpaidWorkSegment], now: Moment
) throws(CommandError) -> UnpaidWorkSegment {
    let start = now.date(on: date, at: input.start)
    let end = now.date(on: date, at: input.end)
    guard end > start else { throw .unpaidWorkEndNotAfterStart }
    guard end <= now.date else { throw .unpaidWorkInFuture }
    let cutoff = now.unpaidWorkCutoff(on: date)
    let overlaps = others.contains { other in
        let otherEnd = other.end ?? min(now.date, cutoff)
        return start < otherEnd && other.start < end
    }
    guard !overlaps else { throw .unpaidWorkOverlap }
    return UnpaidWorkSegment(start: start, end: end)
}
