import Foundation

// 设置页发出的命令 (PRD F12)：工资 (月薪或日薪)、休息模式、作息、菜单栏显示模式、开机自启。
// 校验规则与引导共用 `Validation` (PRD 4.3.5 #1 至 #3)。

/// 修改当月工资 (金额与按月 / 按天)，当月整月生效。
func changeSalary(_ amount: Decimal, basis: PayBasis, state: AppState, now: Moment) throws(CommandError) -> AppState {
    if let error = Validation.salary(amount, basis: basis) { throw error }
    return try updatingProfile(state) { $0.setPay(MonthlySalary(month: now.localDate.yearMonth, amount: amount, basis: basis)) }
}

/// 修改休息模式，当月整月生效 (本月已过去的日子跟着重算)，过去的月份保留当时的模式。
/// 选项都是合法值，没有要拦的输入；大小周按今天所在的周定下大小。
func changeRestMode(_ choice: RestModeChoice, state: AppState, now: Moment) throws(CommandError) -> AppState {
    let today = now.localDate
    return try updatingProfile(state) { $0.setRestMode(choice.mode(on: today), for: today.yearMonth) }
}

/// 修改作息，从今天起生效。
func changeSchedule(_ schedule: WorkSchedule, state: AppState, now: Moment) throws(CommandError) -> AppState {
    if let error = Validation.schedule(schedule) { throw error }
    return try updatingProfile(state) { $0.setSchedule(schedule, from: now.localDate) }
}

func setLaunchAtLogin(_ enabled: Bool, state: AppState) throws(CommandError) -> AppState {
    try updatingProfile(state) { $0.launchAtLogin = enabled }
}

/// 显示模式属于界面设置，引导前也能改。
func setMenuBarMode(_ mode: MenuBarMode, state: AppState) -> AppState {
    var next = state
    next.settings.menuBarMode = mode
    return next
}

/// 月薪、休息模式、作息、开机自启存在引导产生的配置里，引导前不能改。历史里改月薪 (#15) 也用它。
func updatingProfile(_ state: AppState, _ change: (inout Profile) -> Void) throws(CommandError) -> AppState {
    guard var profile = state.profile else { throw .notOnboarded }
    change(&profile)
    var next = state
    next.profile = profile
    return next
}

extension Profile {
    /// 设置 `month` 的工资 (金额与算法)，该月整月生效；其他月份的记录不动 (PRD 4.2.1 #1、#2)。
    mutating func setPay(_ pay: MonthlySalary) {
        salaries = (salaries.filter { $0.month != pay.month } + [pay]).sorted { $0.month < $1.month }
    }

    /// 设置 `month` 的休息模式，该月整月生效；其他月份的记录不动。
    mutating func setRestMode(_ mode: RestMode, for month: YearMonth) {
        restModes = (restModes.filter { $0.month != month } + [MonthlyRestMode(month: month, mode: mode)])
            .sorted { $0.month < $1.month }
    }

    /// 从 `day` 起改用新作息，之前的日子保留当时的作息 (PRD 4.2.3 #2)。
    /// 同一天改多次只留最后一次；新作息与前一个版本相同时不新增版本。
    /// 当天之前没有版本时 (安装当天就改，或系统时间拨回到第一个版本之前)，
    /// 把原来最早的作息挪到前一天生效，安装前的日子仍按它推导。
    mutating func setSchedule(_ schedule: WorkSchedule, from day: LocalDate) {
        let kept = schedules.filter { $0.effectiveFrom < day }
        let earlier = kept.isEmpty
            ? [ScheduleVersion(effectiveFrom: day.adding(days: -1), schedule: schedules[0].schedule)]
            : kept
        schedules = earlier.last?.schedule == schedule
            ? earlier
            : earlier + [ScheduleVersion(effectiveFrom: day, schedule: schedule)]
    }
}
