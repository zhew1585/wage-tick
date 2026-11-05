import Foundation

/// 改变状态的动作。所有状态变化都经 `apply` 执行一条命令完成。
public enum Command: Sendable, Equatable {
    /// 完成 3 步引导 (PRD 4.1.1)。
    case completeOnboarding(OnboardingInput)
    /// 开启或关闭老板路过模式 (PRD 4.7.1 第 3 条)，由全局快捷键或左键菜单发出。
    case toggleBossMode
    /// 给今天记一笔扣钱 (PRD 4.4.1、F5)。
    case addDeduction(DeductionInput)
    /// 修改一笔扣钱记录。
    case editDeduction(id: Int, DeductionInput)
    /// 删除一笔扣钱记录。
    case deleteDeduction(id: Int)
}

/// 引导里牛马填写的内容，未经校验。
public struct OnboardingInput: Sendable, Equatable {
    public let monthlySalary: Decimal
    public let schedule: WorkSchedule
    public let launchAtLogin: Bool

    public init(monthlySalary: Decimal, schedule: WorkSchedule, launchAtLogin: Bool) {
        self.monthlySalary = monthlySalary
        self.schedule = schedule
        self.launchAtLogin = launchAtLogin
    }
}

/// 命令执行后产生的领域事件，外壳据此发系统通知。
/// 本期还没有任何事件 (下班、目标达成留给后续票)。
public enum DomainEvent: Sendable, Equatable {}

/// 命令被拒绝的原因，`message` 是直接展示给牛马的提示文案 (PRD 4.3.5)。
public enum CommandError: Error, Sendable, Equatable {
    case salaryNotPositive
    case endNotAfterStart
    case lunchOutsideWorkHours
    case alreadyOnboarded
    case deductionNotPositive
    case deductionNoteTooLong
    case notAttendanceDay
    case deductionNotFound
    case notOnboarded

    public var message: String {
        switch self {
        case .salaryNotPositive: "月薪得是个正数"
        case .endNotAfterStart: "下班时间要晚于上班时间"
        case .lunchOutsideWorkHours: "午休要在上下班时间之内"
        case .alreadyOnboarded: "已经完成过引导了"
        case .deductionNotPositive: "扣钱金额得大于 0"
        case .deductionNoteTooLong: "备注最多 \(Validation.deductionNoteLimit) 个字"
        case .notAttendanceDay: "今天本来就不上班"
        case .deductionNotFound: "这笔扣钱已经不在了"
        case .notOnboarded: "还没完成引导"
        }
    }
}

/// 核心入口一：在 `now` 时刻对 `state` 执行 `command`，返回新状态与领域事件。
/// 校验失败时抛出 `CommandError`，原状态不受影响。
public func apply(
    _ command: Command,
    to state: AppState,
    at now: Moment
) throws(CommandError) -> (state: AppState, events: [DomainEvent]) {
    switch command {
    case .completeOnboarding(let input):
        return (try completeOnboarding(input, state: state, now: now), [])
    case .toggleBossMode:
        var next = state
        next.settings.bossMode.toggle()
        return (next, [])
    case .addDeduction(let input):
        return (try addDeduction(input, state: state, now: now), [])
    case .editDeduction(let id, let input):
        return (try editDeduction(id: id, input, state: state), [])
    case .deleteDeduction(let id):
        return (try deleteDeduction(id: id, state: state), [])
    }
}

private func completeOnboarding(_ input: OnboardingInput, state: AppState, now: Moment) throws(CommandError) -> AppState {
    guard state.profile == nil else { throw .alreadyOnboarded }
    if let error = Validation.monthlySalary(input.monthlySalary) ?? Validation.schedule(input.schedule) {
        throw error
    }
    let today = now.localDate
    var next = state
    next.profile = Profile(
        installDate: today,
        salaries: [MonthlySalary(month: today.yearMonth, amount: input.monthlySalary)],
        schedule: input.schedule,
        launchAtLogin: input.launchAtLogin
    )
    return next
}
