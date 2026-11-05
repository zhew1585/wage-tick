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
    /// 今天请假 (PRD 4.4.2、F6)：与今天已有的另一半天假合并为全天 (4.3.5 #21)，其余情况替换。
    case requestLeave(Leave)
    /// 修改今天的请假：整条替换，不合并 (4.4.2 #5)。
    case editLeave(Leave)
    /// 撤销今天的请假，当天恢复为普通应出勤日 (4.4.2 #5)；没有请假时什么都不变。
    case cancelLeave
    /// 开始白干计时 (PRD 4.4.3)："我还没走"或"被迫营业"。
    case startUnpaidWork
    /// 停止白干计时："终于下班了"。
    case stopUnpaidWork
    /// 推进到此刻：处理随时间发生的状态变化，依次为白干到 23:59:59 自动停止、累计中目标达成、
    /// 跨过当日计划下班 (产生一次下班事件，PRD 4.6.3)。
    /// 外壳每次刷新时先发它，再取快照。
    case advance
    /// 新建目标 (PRD 4.5.2)，名称与金额未经校验。队列为空时直接累计，否则排到队尾。
    case createGoal(name: String, amount: Decimal)
    /// 编辑排队中或累计中目标的名称和金额 (PRD 4.5.2)，未经校验；改小金额导致累计额已达标时立即完成并激活下一个。
    case editGoal(id: Int, name: String, amount: Decimal)
    /// 删除目标 (PRD 4.5.2)：删除累计中目标时下一个排队目标继承其起算基准，已累计的钱不丢【D5】。
    case deleteGoal(id: Int)
    /// 调整队列顺序 (PRD 4.5.2)：`ids` 是累计中和排队中目标的新顺序，累计中必须在最前【D6】。
    case reorderGoals(ids: [Int])
    /// 切换面板目标区的展开或收起 (PRD F9)，会被记住【O3】。
    case toggleGoalQueueExpanded
    /// 开关下班通知 (PRD 4.7.2)。
    case setOffWorkNotification(Bool)
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
public enum DomainEvent: Sendable, Equatable {
    /// 到达当日计划下班 (PRD 4.6.3)。`message` 是通知正文，已按老板路过模式决定是否含金额，外壳原样发出。
    case offWork(message: String)
}

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
    case leavePercentOutOfRange
    case unpaidWorkUnavailable
    case unpaidWorkAlreadyRunning
    case unpaidWorkNotRunning
    case invalidGoal
    case goalNotFound
    case goalCompleted
    case goalOrderLocked

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
        case .leavePercentOutOfRange: "扣薪比例要在 0% 到 100% 之间"
        // 以下三条 PRD 没给文案：外壳只在快照允许时才提供按钮，正常用不到。
        case .unpaidWorkUnavailable: "下班后或休息日才能白干计时"
        case .unpaidWorkAlreadyRunning: "已经在白干计时了"
        case .unpaidWorkNotRunning: "没有在白干计时"
        case .invalidGoal: "给目标起个名字，金额得大于 0"
        // 以下三条 PRD 没给文案：外壳只对快照允许的行提供编辑、删除，排队中目标只能在排队中一组里拖动，
        // 正常只在列表过期 (如目标刚好达成) 时用到。
        case .goalNotFound: "这个目标已经不在了"
        case .goalCompleted: "已完成的目标不能再改"
        case .goalOrderLocked: "累计中的目标固定在最前"
        }
    }
}

/// 核心入口一：在 `now` 时刻对 `state` 执行 `command`，返回新状态与领域事件。
/// 校验失败时抛出 `CommandError`，原状态不受影响。
/// `holidays` 用于需要判定应出勤日的命令 (如记扣钱、请假、白干计时、新建目标、推进到此刻)；不传时为空表，只按双休。
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
    case .requestLeave(let leave):
        return (try setLeave(leave, mergingWithExisting: true, state: state, now: now, holidays: holidays), [])
    case .editLeave(let leave):
        return (try setLeave(leave, mergingWithExisting: false, state: state, now: now, holidays: holidays), [])
    case .cancelLeave:
        return (cancelLeave(state: state, now: now), [])
    case .startUnpaidWork:
        return (try startUnpaidWork(state: state, now: now, holidays: holidays), [])
    case .stopUnpaidWork:
        return (try stopUnpaidWork(state: state, now: now), [])
    case .advance:
        return advance(state, now: now, holidays: holidays)
    case .createGoal(let name, let amount):
        return (try createGoal(name: name, amount: amount, state: state, now: now, holidays: holidays), [])
    case .editGoal(let id, let name, let amount):
        return try editGoal(id: id, name: name, amount: amount, state: state, now: now, holidays: holidays)
    case .deleteGoal(let id):
        return try deleteGoal(id: id, state: state, now: now, holidays: holidays)
    case .reorderGoals(let ids):
        return (try reorderGoals(ids: ids, state: state), [])
    case .toggleGoalQueueExpanded:
        var next = state
        next.settings.goalQueueExpanded.toggle()
        return (next, [])
    case .setOffWorkNotification(let enabled):
        return (setOffWorkNotification(enabled, state: state), [])
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
