import Foundation

/// 设置页发出的命令 (PRD F12)：月薪、作息、菜单栏显示模式、老板路过快捷键、开机自启。
/// 校验规则与引导共用 `Validation` (PRD 4.3.5 #1 至 #3)。
func applySettings(_ command: Command, to state: AppState, at now: Moment) throws(CommandError) -> AppState {
    var next = state
    switch command {
    case .changeMonthlySalary(let amount):
        if let error = Validation.monthlySalary(amount) { throw error }
        var profile = try onboardedProfile(state)
        profile.setSalary(amount, for: now.localDate.yearMonth)
        next.profile = profile
    case .changeSchedule(let schedule):
        if let error = Validation.schedule(schedule) { throw error }
        var profile = try onboardedProfile(state)
        profile.setSchedule(schedule, from: now.localDate)
        next.profile = profile
    case .setLaunchAtLogin(let enabled):
        var profile = try onboardedProfile(state)
        profile.launchAtLogin = enabled
        next.profile = profile
    case .setMenuBarMode(let mode):
        next.settings.menuBarMode = mode
    case .setBossModeHotkey(let hotkey):
        if let error = Validation.hotkey(hotkey) { throw error }
        next.settings.bossModeHotkey = hotkey
    case .completeOnboarding, .toggleBossMode:
        preconditionFailure("不是设置命令：\(command)")
    }
    return next
}

/// 月薪、作息、开机自启存在引导产生的配置里，引导前不能改。
private func onboardedProfile(_ state: AppState) throws(CommandError) -> Profile {
    guard let profile = state.profile else { throw .notOnboarded }
    return profile
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
