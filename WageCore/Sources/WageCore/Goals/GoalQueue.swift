import Foundation

// 目标队列 (PRD 4.5.2，issue #12)：编辑、删除、排序，以及达标后的完成与激活。
// 攒钱队列 = 累计中目标 + 排队中目标 (按 `AppState.goals` 里的先后，累计中总在排队中之前；排过序后已完成目标都在最前)；
// 同一时间最多一个累计中，有排队中时必有累计中。

/// 编辑排队中或累计中目标的名称和金额 (PRD 4.5.2)。改小金额导致累计额已达标时立即完成并激活下一个。
/// 已完成目标冻结，不能编辑 (不变量 3)。立即完成时的领域事件原样返回。
func editGoal(
    id: Int,
    name: String,
    amount: Decimal,
    state: AppState,
    now: Moment,
    holidays: HolidayTable
) throws(CommandError) -> (state: AppState, events: [DomainEvent]) {
    guard state.profile != nil else { throw .notOnboarded }
    guard let index = state.goals.firstIndex(where: { $0.id == id }) else { throw .goalNotFound }
    let goal = state.goals[index]
    guard !goal.status.isCompleted else { throw .goalCompleted }
    if let error = Validation.goal(name: name, amount: amount) { throw error }
    var next = state
    next.goals[index] = Goal(
        id: goal.id,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        amount: amount,
        status: goal.status
    )
    return completingReachedGoals(next, now: now, holidays: holidays)
}

/// 删除目标 (PRD 4.5.2)。删除累计中目标时，下一个排队目标成为累计中并继承被删目标的起算基准【D5】，
/// 继承来的累计额已达标时立即完成，领域事件原样返回。删除排队中或已完成目标不影响其他目标。
func deleteGoal(
    id: Int,
    state: AppState,
    now: Moment,
    holidays: HolidayTable
) throws(CommandError) -> (state: AppState, events: [DomainEvent]) {
    guard let index = state.goals.firstIndex(where: { $0.id == id }) else { throw .goalNotFound }
    var next = state
    let removed = next.goals.remove(at: index)
    guard case .accumulating(let baseline) = removed.status else { return (next, []) }
    return completingReachedGoals(next.activatingNextGoal(baseline: baseline), now: now, holidays: holidays)
}

/// 调整攒钱队列顺序 (PRD 4.5.2)：`ids` 必须正好是当前全部未完成目标 (累计中 + 排队中)，顺序任意，第一个即累计中【D6】。
/// 第一个换人时：新的第一个成为累计中，继承原累计中目标的起算基准 (已累计的钱转过去)；原累计中目标退回排队中，
/// 原来累计的钱不再带着，下次被激活时和其他排队目标一样，从激活那一刻的起算基准重新起算。继承后已达标的立即完成，零头照常结转，领域事件原样返回。
/// 列表对不上 (目标已完成、已删除或重复) 时提示目标不在了，让外壳按最新快照重来。
func reorderGoals(
    ids: [Int],
    state: AppState,
    now: Moment,
    holidays: HolidayTable
) throws(CommandError) -> (state: AppState, events: [DomainEvent]) {
    let queue = state.goals.filter { !$0.status.isCompleted }
    guard ids.count == queue.count, Set(ids) == Set(queue.map(\.id)) else { throw .goalNotFound }
    guard let current = state.accumulatingGoal, ids.first != current.goal.id else {
        return (state.reorderingQueue(ids), [])
    }
    var next = state
    next.goals[current.index].status = .queued
    return completingReachedGoals(next.reorderingQueue(ids).activatingNextGoal(baseline: current.baseline), now: now, holidays: holidays)
}

/// 累计中目标达标即完成 (PRD 4.5.2)，完成时间取 `now`；下一个排队目标成为累计中，
/// 起算基准 = 上一个的起算基准 + 上一个的金额 (超出零头自动结转)。结转后仍达标的继续完成，直到不达标或队列为空；
/// 队列为空时零头不保留。
/// 目标完成的唯一入口：推进到此刻、编辑 (改小金额)、删除 (继承后已达标) 都经过这里。
/// 每完成一个目标 (#13)：排进待播放的庆祝动画 (见 `GoalCelebration`)；目标达成通知开着时产生一条达成事件，
/// 文案不含金额 (PRD 4.6.3)。结转后连续完成多个时按完成先后各一条。
func completingReachedGoals(
    _ state: AppState,
    now: Moment,
    holidays: HolidayTable
) -> (state: AppState, events: [DomainEvent]) {
    guard let profile = state.profile, state.accumulatingGoal != nil else { return (state, []) }
    let income = Ledger.cumulativeIncome(state: state, profile: profile, now: now, holidays: holidays)
    var next = state
    var events: [DomainEvent] = []
    while let current = next.accumulatingGoal, income - current.baseline >= current.goal.amount {
        next.goals[current.index].status = .completed(at: now.date)
        next.pendingCelebrations = next.pendingCelebrations.filter { $0 != current.goal.id } + [current.goal.id]
        if next.settings.goalReachedNotification {
            events.append(.goalReached(message: NotificationCopy.goalReached(name: current.goal.name)))
        }
        next = next.activatingNextGoal(baseline: current.baseline + current.goal.amount)
    }
    return (next, events)
}

extension AppState {
    /// 未完成目标按 `ids` 的顺序排在已完成目标之后；`ids` 已校验正好是全部未完成目标。状态不变。
    func reorderingQueue(_ ids: [Int]) -> AppState {
        var next = self
        next.goals = goals.filter(\.status.isCompleted) + ids.compactMap { id in goals.first { $0.id == id } }
        return next
    }

    /// 第一个排队中目标成为累计中，起算基准为 `baseline`；没有排队中目标时不变。
    func activatingNextGoal(baseline: Decimal) -> AppState {
        guard let index = goals.firstIndex(where: \.status.isQueued) else { return self }
        var next = self
        next.goals[index].status = .accumulating(baseline: baseline)
        return next
    }
}

extension GoalStatus {
    /// 是否已完成；累计中和排队中都在队列里。
    var isCompleted: Bool {
        if case .completed = self { true } else { false }
    }
}
