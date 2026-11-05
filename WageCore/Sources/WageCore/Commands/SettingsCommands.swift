import Foundation

// 设置页发出的命令 (PRD F12)：月薪、作息、菜单栏显示模式、老板路过快捷键、开机自启。
// 校验规则与引导共用 `Validation` (PRD 4.3.5 #1 至 #3)。

/// 修改当月月薪，当月整月生效。
func changeMonthlySalary(_ amount: Decimal, state: AppState, now: Moment) throws(CommandError) -> AppState {
    if let error = Validation.monthlySalary(amount) { throw error }
    return try updatingProfile(state) { $0.setSalary(amount, for: now.localDate.yearMonth) }
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

/// 快捷键属于界面设置，引导前也能改。
func setBossModeHotkey(_ hotkey: Hotkey, state: AppState) throws(CommandError) -> AppState {
    if let error = Validation.hotkey(hotkey) { throw error }
    var next = state
    next.settings.bossModeHotkey = hotkey
    return next
}

/// 月薪、作息、开机自启存在引导产生的配置里，引导前不能改。
private func updatingProfile(_ state: AppState, _ change: (inout Profile) -> Void) throws(CommandError) -> AppState {
    guard var profile = state.profile else { throw .notOnboarded }
    change(&profile)
    var next = state
    next.profile = profile
    return next
}

extension Profile {
    /// 设置 `month` 的月薪，该月整月生效；其他月份的记录不动 (PRD 4.2.1 #1、#2)。
    mutating func setSalary(_ amount: Decimal, for month: YearMonth) {
        salaries = (salaries.filter { $0.month != month } + [MonthlySalary(month: month, amount: amount)])
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
