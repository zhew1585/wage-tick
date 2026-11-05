import Foundation

/// 扣钱表单里牛马填写的内容，未经校验 (PRD 4.4.1)。
public struct DeductionInput: Sendable, Equatable {
    public let amount: DeductionAmount
    public let reason: DeductionReason?
    public let note: String

    public init(amount: DeductionAmount, reason: DeductionReason?, note: String) {
        self.amount = amount
        self.reason = reason
        self.note = note
    }
}

extension Validation {
    /// 扣钱备注最多 50 字 (PRD 4.7.2)。
    public static let deductionNoteLimit = 50

    /// 扣钱数值必须大于 0 (PRD 4.3.5 #5)，按金额、按日薪百分比同一条规则；备注最多 50 字。
    public static func deduction(_ input: DeductionInput) -> CommandError? {
        guard input.amount.value > 0 else { return .deductionNotPositive }
        guard input.note.count <= deductionNoteLimit else { return .deductionNoteTooLong }
        return nil
    }
}

/// 给 `date` 记一笔扣钱：今天来自「今天扣钱了」，过去的日子来自历史补记 (PRD 4.4.1、4.6.1)。
/// 只能记在今天或过去的应出勤日 (PRD 4.3.5 #7、#8)。
func addDeduction(
    _ input: DeductionInput, on date: LocalDate, state: AppState, now: Moment, holidays: HolidayTable
) throws(CommandError) -> AppState {
    guard state.profile != nil else { throw .notOnboarded }
    if let error = Validation.deduction(input) { throw error }
    try requireDeductibleDay(date, now: now, holidays: holidays)
    let deduction = Deduction(id: state.nextDeductionID, input: input)
    var record = state.dayRecord(on: date) ?? DayRecord(date: date)
    record.deductions.append(deduction)
    return state.replacingDayRecord(record)
}

/// 改 `date` 的一笔扣钱，先后位置不变。与新记同样只能改今天或过去的应出勤日。
func editDeduction(
    id: Int, _ input: DeductionInput, on date: LocalDate, state: AppState, now: Moment, holidays: HolidayTable
) throws(CommandError) -> AppState {
    if let error = Validation.deduction(input) { throw error }
    guard var record = state.record(on: date, containingDeduction: id) else { throw .deductionNotFound }
    try requireDeductibleDay(date, now: now, holidays: holidays)
    record.deductions = record.deductions.map { $0.id == id ? Deduction(id: id, input: input) : $0 }
    return state.replacingDayRecord(record)
}

/// 删除 `date` 的一笔扣钱；日记录因此变空时一并删掉。
/// 不看这天是否应出勤：单日覆盖或节假日表更新后变成不上班日的那天，已有的扣钱要能删掉 (#14 遗留)。
func deleteDeduction(id: Int, on date: LocalDate, state: AppState) throws(CommandError) -> AppState {
    guard var record = state.record(on: date, containingDeduction: id) else { throw .deductionNotFound }
    record.deductions.removeAll { $0.id == id }
    return state.replacingDayRecord(record)
}

/// 记扣钱的日子：不应出勤的日子不行 (PRD 4.3.5 #8)，未来不行 (只能请假和单日覆盖，PRD 4.6.1)。
/// 先看应出勤，与单日详情里入口不可用的原因一致 (见 `DayEditing`)。
private func requireDeductibleDay(_ date: LocalDate, now: Moment, holidays: HolidayTable) throws(CommandError) {
    guard AttendanceRule(holidays: holidays).isAttendanceDay(date) else { throw .notAttendanceDay }
    guard date <= now.localDate else { throw .futureDate }
}

extension AppState {
    /// `date` 的日记录，且其中有这笔扣钱；不在这一天的视为找不到。
    func record(on date: LocalDate, containingDeduction id: Int) -> DayRecord? {
        dayRecord(on: date).flatMap { record in
            record.deductions.contains { $0.id == id } ? record : nil
        }
    }

    /// 新扣钱记录的标识：比现有最大的大 1。
    var nextDeductionID: Int {
        (dayRecords.flatMap(\.deductions).map(\.id).max() ?? 0) + 1
    }

    /// 用 `record` 替换同一天的日记录 (没有则插入)，保持按日期升序；空记录直接去掉。
    func replacingDayRecord(_ record: DayRecord) -> AppState {
        var next = self
        let others = dayRecords.filter { $0.date != record.date }
        next.dayRecords = (record.isEmpty ? others : others + [record]).sorted { $0.date < $1.date }
        return next
    }
}
