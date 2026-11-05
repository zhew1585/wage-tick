import Foundation

/// 改变状态的动作。所有状态变化都经 `apply` 执行一条命令完成。
public enum Command: Sendable, Equatable {
    /// 完成 3 步引导 (PRD 4.1.1)。
    case completeOnboarding(OnboardingInput)
    /// 开启或关闭老板路过模式 (PRD 4.7.1 第 3 条)，由全局快捷键或左键菜单发出。
    case toggleBossMode
    /// 修改当月月薪，对当月整月生效 (PRD 4.2.1 #1)。
    case changeMonthlySalary(Decimal)
    /// 修改作息，从今天起生效 (PRD 4.2.3 #2)。
    case changeSchedule(WorkSchedule)
    /// 切换菜单栏显示模式 (PRD 4.7.1 第 2 条)。
    case setMenuBarMode(MenuBarMode)
    /// 修改老板路过快捷键 (PRD 4.7.2)。
    case setBossModeHotkey(Hotkey)
    /// 开关开机自动启动 (PRD 4.7.2)。
    case setLaunchAtLogin(Bool)
    /// 给今天记一笔扣钱 (PRD 4.4.1、F5)。
    case addDeduction(DeductionInput)
    /// 修改今天的一笔扣钱记录。
    case editDeduction(id: Int, DeductionInput)
    /// 删除今天的一笔扣钱记录。
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
    case notOnboarded
    case hotkeyKeyInvalid
    case hotkeyModifiersInvalid
    case deductionNotPositive
    case deductionNoteTooLong
    case notAttendanceDay
    case deductionNotFound

    public var message: String {
        switch self {
        case .salaryNotPositive: "月薪得是个正数"
        case .endNotAfterStart: "下班时间要晚于上班时间"
        case .lunchOutsideWorkHours: "午休要在上下班时间之内"
        case .alreadyOnboarded: "已经完成过引导了"
        case .notOnboarded: "还没完成引导"
        case .hotkeyKeyInvalid: "主键只能是字母或数字"
        case .hotkeyModifiersInvalid: "快捷键要按住两个以上修饰键，且包含 ⌃ 或 ⌘"
        case .deductionNotPositive: "扣钱金额得大于 0"
        case .deductionNoteTooLong: "备注最多 \(Validation.deductionNoteLimit) 个字"
        case .notAttendanceDay: "今天本来就不上班"
        case .deductionNotFound: "这笔扣钱已经不在了"
        }
    }
}

/// 核心入口一：在 `now` 时刻对 `state` 执行 `command`，返回新状态与领域事件。
/// 校验失败时抛出 `CommandError`，原状态不受影响。
/// `holidays` 用于需要判定应出勤日的命令 (如记扣钱)；不传时为空表，只按双休。
public func apply(
    _ command: Command,
    to state: AppState,
    at now: Moment,
    holidays: HolidayTable = .empty
) throws(CommandError) -> (state: AppState, events: [DomainEvent]) {
    switch command {
    case .completeOnboarding(let input):
        return (try completeOnboarding(input, state: state, now: now), [])
    case .toggleBossMode:
        var next = state
        next.settings.bossMode.toggle()
        return (next, [])
    case .changeMonthlySalary(let amount):
        return (try changeMonthlySalary(amount, state: state, now: now), [])
    case .changeSchedule(let schedule):
        return (try changeSchedule(schedule, state: state, now: now), [])
    case .setMenuBarMode(let mode):
        return (setMenuBarMode(mode, state: state), [])
    case .setBossModeHotkey(let hotkey):
        return (try setBossModeHotkey(hotkey, state: state), [])
    case .setLaunchAtLogin(let enabled):
        return (try setLaunchAtLogin(enabled, state: state), [])
    case .addDeduction(let input):
        return (try addDeduction(input, state: state, now: now, holidays: holidays), [])
    case .editDeduction(let id, let input):
        return (try editDeduction(id: id, input, state: state, now: now), [])
    case .deleteDeduction(let id):
        return (try deleteDeduction(id: id, state: state, now: now), [])
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
