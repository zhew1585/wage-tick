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

/// 给今天记一笔扣钱。只能记在应出勤日 (PRD 4.3.5 #8)；补记过去的日子留给历史编辑。
func addDeduction(_ input: DeductionInput, state: AppState, now: Moment) throws(CommandError) -> AppState {
    guard state.profile != nil else { throw .notOnboarded }
    if let error = Validation.deduction(input) { throw error }
    let today = now.localDate
    guard AttendanceRule.isAttendanceDay(today) else { throw .notAttendanceDay }
    let deduction = Deduction(id: state.nextDeductionID, input: input)
    var record = state.dayRecord(on: today) ?? DayRecord(date: today)
    record.deductions.append(deduction)
    return state.replacingDayRecord(record)
}

/// 改一笔已有的扣钱，日期和先后位置不变。
func editDeduction(id: Int, _ input: DeductionInput, state: AppState) throws(CommandError) -> AppState {
    if let error = Validation.deduction(input) { throw error }
    guard var record = state.dayRecords.first(where: { $0.deductions.contains { $0.id == id } }) else {
        throw .deductionNotFound
    }
    record.deductions = record.deductions.map { $0.id == id ? Deduction(id: id, input: input) : $0 }
    return state.replacingDayRecord(record)
}

/// 删除一笔扣钱；日记录因此变空时一并删掉。
func deleteDeduction(id: Int, state: AppState) throws(CommandError) -> AppState {
    guard var record = state.dayRecords.first(where: { $0.deductions.contains { $0.id == id } }) else {
        throw .deductionNotFound
    }
    record.deductions.removeAll { $0.id == id }
    return state.replacingDayRecord(record)
}

extension AppState {
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
