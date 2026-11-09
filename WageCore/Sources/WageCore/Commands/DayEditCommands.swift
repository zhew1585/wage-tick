import Foundation

// 历史编辑 (PRD 4.6.1、F11，#15)：在单日详情里改某一天，或改某个月的月薪。
// 一切推导内容 (日薪、结算、本月累计、目标累计额) 都从状态实时推导，编辑后自然重算；已完成目标只存完成时间，不受影响 (AC-GOAL-08)。
// 编辑让当前目标达标时当场完成，见 `completingGoalsAfterEdit`。

/// 对某一天的编辑 (PRD 4.6.1 可编辑内容)：
/// - 过去和今天：扣钱、请假、白干段、单日覆盖
/// - 未来：请假、单日覆盖
/// 扣钱、请假只能落在应出勤日 (PRD 4.3.5 #8)；删除扣钱、撤销请假不看应出勤，变成不上班日的那天也能清掉 (#14 遗留)。
public enum DayEdit: Sendable, Equatable {
    case addDeduction(DeductionInput)
    case editDeduction(id: Int, DeductionInput)
    case deleteDeduction(id: Int)
    /// 请假或修改请假：一天只有一条，已有时整条替换。
    case setLeave(Leave)
    /// 撤销请假；没有请假时什么都不变。
    case cancelLeave
    /// 设置单日覆盖 (PRD 4.2.2)，任意日期。
    case setOverride(DayOverride)
    /// 撤销单日覆盖，回到按规则判定；没有覆盖时什么都不变。
    case clearOverride
    /// 补记一段白干 (PRD 4.4.3 #5)，结束可以在次日 (跨过零点)，最晚到这天的自动停止时刻。
    case addUnpaidWork(UnpaidWorkInput)
    /// 修改这天第 `index` 段白干 (按开始时刻先后，与单日详情里的顺序一致)；计时中的那段不能改。
    case editUnpaidWork(index: Int, UnpaidWorkInput)
    /// 删除这天第 `index` 段白干，计时中的那段也可以删。
    case deleteUnpaidWork(index: Int)
}

/// 执行对 `date` 的编辑。历史从安装当月开始 (PRD 4.1.1)，更早的日子没有历史，拒绝。
func editDay(
    _ date: LocalDate, _ edit: DayEdit, state: AppState, now: Moment, holidays: HolidayTable
) throws(CommandError) -> AppState {
    guard let profile = state.profile else { throw .notOnboarded }
    guard date.yearMonth >= profile.installDate.yearMonth else { throw .dateOutOfRange }
    switch edit {
    case .addDeduction(let input):
        return try addDeduction(input, on: date, state: state, now: now, holidays: holidays)
    case .editDeduction(let id, let input):
        return try editDeduction(id: id, input, on: date, state: state, now: now, holidays: holidays)
    case .deleteDeduction(let id):
        return try deleteDeduction(id: id, on: date, state: state)
    case .setLeave(let leave):
        return try setLeave(leave, on: date, state: state, holidays: holidays)
    case .cancelLeave:
        return cancelLeave(on: date, state: state)
    case .setOverride(let override):
        return state.settingOverride(override, on: date)
    case .clearOverride:
        return state.settingOverride(nil, on: date)
    case .addUnpaidWork(let input):
        return try addUnpaidWork(input, on: date, state: state, now: now, holidays: holidays)
    case .editUnpaidWork(let index, let input):
        return try editUnpaidWork(index: index, input, on: date, state: state, now: now, holidays: holidays)
    case .deleteUnpaidWork(let index):
        return try deleteUnpaidWork(index: index, on: date, state: state)
    }
}

/// 历史编辑后当前目标的累计额随之变化 (PRD 4.5.2「编辑历史只影响当前累计中目标」)，因此达标的立即完成：
/// 走目标完成的唯一入口 `completingReachedGoals` (发达成通知、排庆祝动画、激活下一个)；已完成目标冻结不动。
/// 编辑可能改了单日覆盖、月薪，节假日表按编辑后的状态重新并一次。
func completingGoalsAfterEdit(_ state: AppState, now: Moment, holidays: HolidayTable) -> (state: AppState, events: [DomainEvent]) {
    completingReachedGoals(state, now: now, holidays: holidays.overlaying(state))
}

/// 改 `month` 的工资 (金额与按月 / 按天)，该月整月生效 (PRD 4.2.1)，限安装当月至本月。改本月时未来月份沿用 (4.2.1 #3)。
/// 改过去的月份时，下个月若没有单独设置过工资，先把它钉在原来的金额与算法上：
/// 否则「未来月份沿用最近一次设置」会让之后的月份 (含本月) 跟着变 (AC-CAL-05 本月不变)。
func setSalary(_ amount: Decimal, basis: PayBasis, for month: YearMonth, state: AppState, now: Moment) throws(CommandError) -> AppState {
    guard let installMonth = state.profile?.installDate.yearMonth else { throw .notOnboarded }
    if let error = Validation.salary(amount, basis: basis) { throw error }
    let current = now.localDate.yearMonth
    guard month >= installMonth, month <= current else { throw .dateOutOfRange }
    return try updatingProfile(state) { profile in
        if month < current, !profile.salaries.contains(where: { $0.month == month.next }) {
            let kept = profile.pay(for: month.next)
            profile.setPay(MonthlySalary(month: month.next, amount: kept.amount, basis: kept.basis))
        }
        profile.setPay(MonthlySalary(month: month, amount: amount, basis: basis))
    }
}

extension AppState {
    /// 设置或撤销 (nil) `date` 的单日覆盖；日记录因此变空时一并删掉。
    func settingOverride(_ override: DayOverride?, on date: LocalDate) -> AppState {
        var record = dayRecord(on: date) ?? DayRecord(date: date)
        record.override = override
        return replacingDayRecord(record)
    }
}
