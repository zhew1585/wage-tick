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

    public var message: String {
        switch self {
        case .salaryNotPositive: "月薪得是个正数"
        case .endNotAfterStart: "下班时间要晚于上班时间"
        case .lunchOutsideWorkHours: "午休要在上下班时间之内"
        case .alreadyOnboarded: "已经完成过引导了"
        case .notOnboarded: "还没完成引导"
        case .hotkeyKeyInvalid: "主键只能是字母或数字"
        case .hotkeyModifiersInvalid: "快捷键要按住两个以上修饰键，且包含 ⌃ 或 ⌘"
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
    case .changeMonthlySalary, .changeSchedule, .setMenuBarMode, .setBossModeHotkey, .setLaunchAtLogin:
        return (try applySettings(command, to: state, at: now), [])
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
