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
    /// 推进到此刻：处理随时间发生的状态变化，依次为白干到 23:59:59 自动停止、累计中目标达成 (产生一次达成事件)、
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
    /// 开关目标达成通知 (PRD 4.7.2)。
    case setGoalReachedNotification(Bool)
    /// 面板开始播放目标达成庆祝动画时确认，同一目标不再播放 (AC-GPRG-04)。
    case acknowledgeCelebration(goalID: Int)
    /// 历史编辑 (PRD 4.6.1、F11)：在单日详情里改某一天，可编辑范围见 `DayEdit`。
    case editDay(LocalDate, DayEdit)
    /// 在历史里改某个月的月薪 (PRD 4.2.1、4.6.1)，限安装当月至本月：过去的月份只影响该月；
    /// 本月与 `changeMonthlySalary` 相同，未来月份沿用。
    case setMonthlySalary(YearMonth, Decimal)
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
    /// 累计中目标完成 (PRD 4.6.3)。`message` 是通知正文，不含金额，外壳原样发出。
    case goalReached(message: String)
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
    case dateOutOfRange
    case futureDate
    case unpaidWorkEndNotAfterStart
    case unpaidWorkOverlap
    case unpaidWorkInFuture
    case unpaidWorkNotFound

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
        // 以下为历史编辑 (#15) 的提示，PRD 没给文案。`futureDate` 也作为单日详情里入口不可用的原因展示。
        case .dateOutOfRange: "这天不在历史范围内"
        case .futureDate: "还没到这一天，只能请假或设置单日覆盖"
        case .unpaidWorkEndNotAfterStart: "结束时间要晚于开始时间"
        case .unpaidWorkOverlap: "和这天已有的白干段重叠了"
        case .unpaidWorkInFuture: "还没到这个时间"
        case .unpaidWorkNotFound: "这段白干已经不在了"
        }
    }
}

/// 核心入口一：在 `now` 时刻对 `state` 执行 `command`，返回新状态与领域事件。
/// 校验失败时抛出 `CommandError`，原状态不受影响。
/// `holidays` 用于需要判定应出勤日的命令 (如记扣钱、请假、白干计时、新建目标、推进到此刻)；不传时为空表，只按双休。
/// 状态里的单日覆盖在这里并入节假日表，各命令拿到的 `holidays` 已带上覆盖 (PRD 4.2.2)。
public func apply(
    _ command: Command,
    to state: AppState,
    at now: Moment,
    holidays: HolidayTable = .empty
) throws(CommandError) -> (state: AppState, events: [DomainEvent]) {
    let holidays = holidays.overlaying(state.dayRecords)
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
    // 面板上的扣钱、请假只作用于今天 (#7、#8)，与历史编辑走同一套逻辑；不检查历史范围，
    // 系统时间被拨回到安装当月之前时 (PRD 4.3.5 #11) 今天的操作照旧。
    case .addDeduction(let input):
        return (try addDeduction(input, on: now.localDate, state: state, now: now, holidays: holidays), [])
    case .editDeduction(let id, let input):
        return (try editDeduction(id: id, input, on: now.localDate, state: state, now: now, holidays: holidays), [])
    case .deleteDeduction(let id):
        return (try deleteDeduction(id: id, on: now.localDate, state: state), [])
    case .requestLeave(let leave):
        return (try setLeave(leave, mergingWithExisting: true, on: now.localDate, state: state, holidays: holidays), [])
    case .editLeave(let leave):
        return (try setLeave(leave, mergingWithExisting: false, on: now.localDate, state: state, holidays: holidays), [])
    case .cancelLeave:
        return (cancelLeave(on: now.localDate, state: state), [])
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
    case .setGoalReachedNotification(let enabled):
        return (setGoalReachedNotification(enabled, state: state), [])
    case .acknowledgeCelebration(let goalID):
        return (acknowledgeCelebration(goalID: goalID, state: state), [])
    case .editDay(let date, let edit):
        return completingGoalsAfterEdit(try editDay(date, edit, state: state, now: now, holidays: holidays), now: now, holidays: holidays)
    case .setMonthlySalary(let month, let amount):
        return completingGoalsAfterEdit(try setMonthlySalary(amount, for: month, state: state, now: now), now: now, holidays: holidays)
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
