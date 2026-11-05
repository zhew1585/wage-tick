import Foundation
import Testing
import WageCore

/// 在 `now` 时刻执行一条命令，返回新状态。
private func applied(_ command: Command, to state: AppState, at now: Moment) throws -> AppState {
    try apply(command, to: state, at: now).state
}

/// 执行命令，返回被拒绝的原因；成功时为 nil。
private func rejection(_ command: Command, to state: AppState, at now: Moment = standardDay(15, 0)) -> CommandError? {
    do {
        _ = try apply(command, to: state, at: now)
        return nil
    } catch {
        return error
    }
}

/// 标准算例作息，只把计划下班改到 `endHour`。
private func scheduleEnding(at endHour: Int) -> WorkSchedule {
    WorkSchedule(start: standardSchedule.start, end: TimeOfDay(hour: endHour, minute: 0), lunch: standardSchedule.lunch)
}

private func attendancePanel(_ snap: Snapshot) throws -> AttendancePanel {
    guard case .attendance(let panel) = try #require(snap.panel).body else {
        Issue.record("不是应出勤日的面板")
        throw CancellationError()
    }
    return panel
}

@Suite("设置：修改月薪")
struct ChangeSalaryTests {
    @Test("AC-SET-01 本月中旬把月薪从 20000 改为 22000：本月已过日子全部按 1100 重算")
    func wholeMonthRecomputed() throws {
        let state = try applied(.changeMonthlySalary(22000), to: try onboarded(), at: standardDay(15, 0))
        let snap = snapshot(of: state, at: standardDay(18, 30))

        // 2 月 11 日之前 7 个应出勤日 + 今天已下班，共 8 天 × 1100。
        let today = try #require(snap.today)
        #expect(today.dailyWage == 1100)
        #expect(today.monthToDate == 8800)
        #expect(snap.menuBar.text == "1100.0000")
    }

    @Test("PRD 4.2.1 #2 已经过去的月份保留当时的月薪")
    func pastMonthKeepsOldSalary() throws {
        // 3 月 2 日 (周一) 改月薪，2 月仍按 20000 ÷ 20 = 1000。
        let state = try applied(.changeMonthlySalary(33000), to: try onboarded(), at: moment(2026, 3, 2, 11, 0))

        #expect(snapshot(of: state, at: moment(2026, 2, 27, 18, 30)).today?.dailyWage == 1000)
        #expect(snapshot(of: state, at: moment(2026, 3, 2, 18, 30)).today?.dailyWage == 1500)
    }

    @Test("PRD 4.2.1 #3 未来月份沿用最近一次设置的月薪")
    func futureMonthFollowsLatest() throws {
        let state = try applied(.changeMonthlySalary(22000), to: try onboarded(), at: standardDay(15, 0))

        // 2026 年 3 月只按双休有 22 个应出勤日：22000 ÷ 22 = 1000。
        #expect(snapshot(of: state, at: moment(2026, 3, 2, 18, 30)).today?.dailyWage == 1000)
    }

    @Test("同一个月改两次：以最后一次为准")
    func lastChangeInMonthWins() throws {
        let once = try applied(.changeMonthlySalary(22000), to: try onboarded(), at: standardDay(11, 0))
        let twice = try applied(.changeMonthlySalary(24000), to: once, at: standardDay(15, 0))

        #expect(snapshot(of: twice, at: standardDay(18, 30)).today?.dailyWage == 1200)
    }

    @Test(
        "PRD 4.3.5 #1 设置页月薪校验与引导一致：为 0、负数或超过 2 位小数时提示「月薪得是个正数」",
        arguments: ["0", "-1", "20000.123"]
    )
    func invalidSalaryIsRejected(text: String) throws {
        let state = try onboarded()
        let error = rejection(.changeMonthlySalary(Decimal(string: text)!), to: state)

        #expect(error == .salaryNotPositive)
        #expect(error?.message == "月薪得是个正数")
        #expect(error == Validation.monthlySalary(Decimal(string: text)!))
    }

    @Test("未完成引导时不能改月薪")
    func requiresOnboarding() {
        #expect(rejection(.changeMonthlySalary(22000), to: AppState()) == .notOnboarded)
    }
}

@Suite("设置：修改作息")
struct ChangeScheduleTests {
    @Test("AC-SET-02 15:00 把下班改为 19:00：今日进度、倒计时立即按新作息重算")
    func todayRecomputedImmediately() throws {
        let state = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(), at: standardDay(15, 0))
        let snap = snapshot(of: state, at: standardDay(15, 0))

        // 新作息有效工时 8 小时，10:00 至 15:00 扣午休已过 4 小时，正好一半。
        let earnings = try #require(snap.today?.earnings)
        #expect(earnings.progress == Decimal(string: "0.5")!)
        #expect(snap.menuBar.text == "500.0000")
        let panel = try attendancePanel(snap)
        #expect(panel.stats.first == StatItem(title: "距离下班", value: "4:00:00"))
        #expect(panel.progress?.label == "已工作 4 / 8 小时")
    }

    @Test("AC-SET-02 昨天结算不变：昨天仍按当时作息，18:30 已下班")
    func yesterdayKeepsOldSchedule() throws {
        let state = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(), at: standardDay(15, 0))
        let yesterday = snapshot(of: state, at: moment(2026, 2, 10, 18, 30))

        #expect(yesterday.today?.status == .offWork)
        #expect(yesterday.menuBar.text == "1000.0000")
    }

    @Test("PRD 4.2.3 #2 从今天起生效：之后的日子都按新作息")
    func laterDaysUseNewSchedule() throws {
        let state = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(), at: standardDay(15, 0))

        #expect(snapshot(of: state, at: moment(2026, 2, 12, 18, 30)).today?.status == .working)
    }

    @Test("作息按生效日期分版本：每次修改只影响修改当天及以后")
    func versionsByEffectiveDate() throws {
        let first = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(), at: standardDay(15, 0))
        let second = try applied(.changeSchedule(scheduleEnding(at: 20)), to: first, at: moment(2026, 2, 12, 9, 0))
        let statusAt1830 = { (day: Int) in snapshot(of: second, at: moment(2026, 2, day, 18, 30)).today?.status }
        let statusAt1930 = { (day: Int) in snapshot(of: second, at: moment(2026, 2, day, 19, 30)).today?.status }

        #expect(statusAt1830(10) == .offWork)  // 18:00 下班
        #expect(statusAt1830(11) == .working)  // 19:00 下班
        #expect(statusAt1930(11) == .offWork)
        #expect(statusAt1930(12) == .working)  // 20:00 下班
        #expect(statusAt1930(13) == .working)
    }

    @Test("同一天改两次：以最后一次为准，昨天仍不受影响")
    func sameDayChangesCollapse() throws {
        let first = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(), at: standardDay(15, 0))
        let reverted = try applied(.changeSchedule(standardSchedule), to: first, at: standardDay(15, 30))

        #expect(snapshot(of: reverted, at: standardDay(18, 30)).today?.status == .offWork)
        #expect(snapshot(of: reverted, at: moment(2026, 2, 10, 18, 30)).today?.status == .offWork)
        #expect(snapshot(of: reverted, at: moment(2026, 2, 12, 18, 30)).today?.status == .offWork)
    }

    @Test("PRD 4.2.3 #3 作息不影响结算：改作息后本月累计里已过日子不变")
    func scheduleDoesNotChangeSettlement() throws {
        let state = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(), at: standardDay(15, 0))

        #expect(snapshot(of: state, at: standardDay(19, 30)).today?.monthToDate == 8000)
    }

    @Test("PRD 4.3.5 #2 设置页作息校验与引导一致：下班不晚于上班")
    func endMustBeAfterStart() throws {
        let schedule = WorkSchedule(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 9, minute: 0), lunch: nil)
        let error = rejection(.changeSchedule(schedule), to: try onboarded())

        #expect(error == .endNotAfterStart)
        #expect(error?.message == "下班时间要晚于上班时间")
    }

    @Test("PRD 4.3.5 #3 设置页作息校验与引导一致：午休不在上下班之内")
    func lunchMustBeInsideWorkHours() throws {
        let lunch = LunchBreak(start: TimeOfDay(hour: 17, minute: 0), end: TimeOfDay(hour: 19, minute: 0))
        let schedule = WorkSchedule(start: standardSchedule.start, end: standardSchedule.end, lunch: lunch)
        let error = rejection(.changeSchedule(schedule), to: try onboarded())

        #expect(error == .lunchOutsideWorkHours)
        #expect(error?.message == "午休要在上下班时间之内")
    }

    @Test("未完成引导时不能改作息")
    func requiresOnboarding() {
        #expect(rejection(.changeSchedule(standardSchedule), to: AppState()) == .notOnboarded)
    }

    @Test("作息版本重启后保留：状态存成 JSON 再读回，昨天和今天仍各按各的作息")
    func versionsSurviveRestart() throws {
        let state = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(), at: standardDay(15, 0))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(snapshot(of: restored, at: moment(2026, 2, 10, 18, 30)).today?.status == .offWork)
        #expect(snapshot(of: restored, at: standardDay(18, 30)).today?.status == .working)
    }

    @Test("读回状态时作息版本不能为空，版本里的作息照常校验")
    func corruptVersionsAreRejected() throws {
        let state = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(), at: standardDay(15, 0))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var profile = try #require(json["profile"] as? [String: Any])
        let decode = { (profile: [String: Any]) throws -> AppState in
            json["profile"] = profile
            return try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        }

        profile["schedules"] = []
        #expect(throws: DecodingError.self) { try decode(profile) }
        profile["schedules"] = [["effectiveFrom": ["year": 2026, "month": 2, "day": 11],
                                 "schedule": ["start": ["hour": 18, "minute": 0], "end": ["hour": 9, "minute": 0]]]]
        #expect(throws: DecodingError.self) { try decode(profile) }
    }
}

@Suite("设置：菜单栏显示模式")
struct MenuBarModeTests {
    private func inMode(_ mode: MenuBarMode) throws -> AppState {
        try applied(.setMenuBarMode(mode), to: try onboarded(), at: standardDay(9, 0))
    }

    @Test("PRD 4.7.2 默认金额模式")
    func defaultsToAmount() throws {
        #expect(snapshot(of: try onboarded(), at: standardDay(15, 0)).settings.menuBarMode == .amount)
    }

    @Test("AC-BAR-07 进度模式：15:00 显示 57.14%")
    func progressMode() throws {
        let snap = snapshot(of: try inMode(.progress), at: standardDay(15, 0))

        #expect(snap.menuBar == MenuBarDisplay(pose: .grinding, text: "57.14%"))
        #expect(snap.settings.menuBarMode == .progress)
    }

    @Test(
        "PRD 4.7.1 #2 进度模式各状态：固定 2 位小数，宽度不跳",
        arguments: [(9, 30, "0.00%"), (11, 0, "14.29%"), (12, 30, "28.57%"), (18, 30, "100.00%")]
    )
    func progressModeIsFixedWidth(hour: Int, minute: Int, text: String) throws {
        #expect(snapshot(of: try inMode(.progress), at: standardDay(hour, minute)).menuBar.text == text)
    }

    @Test("PRD 4.7.1 #2 进度模式休息日不显示数字")
    func progressModeRestDay() throws {
        #expect(snapshot(of: try inMode(.progress), at: moment(2026, 2, 14, 11, 0)).menuBar == MenuBarDisplay(pose: .sunbathing, text: nil))
    }

    @Test("AC-BAR-08 仅图标模式：只显示小牛，姿势照常")
    func iconOnlyMode() throws {
        #expect(snapshot(of: try inMode(.iconOnly), at: standardDay(15, 0)).menuBar == MenuBarDisplay(pose: .grinding, text: nil))
    }

    @Test("AC-BOSS-01、02 进度模式下老板路过：隐藏百分比，关闭后恢复为进度模式")
    func bossModeOverridesAndRestoresMode() throws {
        let on = try applied(.toggleBossMode, to: try inMode(.progress), at: standardDay(15, 0))
        let off = try applied(.toggleBossMode, to: on, at: standardDay(15, 0))

        #expect(snapshot(of: on, at: standardDay(15, 0)).menuBar.text == nil)
        #expect(snapshot(of: off, at: standardDay(15, 0)).menuBar.text == "57.14%")
    }

    @Test("切回金额模式：恢复 4 位小数的今日已赚")
    func backToAmount() throws {
        let state = try applied(.setMenuBarMode(.amount), to: try inMode(.iconOnly), at: standardDay(15, 0))

        #expect(snapshot(of: state, at: standardDay(15, 0)).menuBar.text == "571.4286")
    }

    @Test("设置页选项文案", arguments: [(MenuBarMode.amount, "金额"), (.progress, "进度"), (.iconOnly, "仅图标")])
    func labels(mode: MenuBarMode, label: String) {
        #expect(mode.label == label)
    }

    @Test("显示模式重启后保留；没有显示模式的旧设置照常读回，取默认金额模式")
    func persistence() throws {
        let state = try inMode(.progress)
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        #expect(restored == state)

        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(try onboarded())) as? [String: Any])
        var settings = try #require(json["settings"] as? [String: Any])
        settings["menuBarMode"] = nil
        json["settings"] = settings
        let old = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(snapshot(of: old, at: standardDay(15, 0)).menuBar.text == "571.4286")
    }
}

@Suite("设置：老板路过快捷键")
struct BossModeHotkeyTests {
    @Test("修改后快照给出新快捷键，供外壳重新注册与菜单显示")
    func changeHotkey() throws {
        let hotkey = Hotkey(key: "K", modifiers: [.command, .shift])
        let state = try applied(.setBossModeHotkey(hotkey), to: try onboarded(), at: standardDay(15, 0))

        #expect(snapshot(of: state, at: standardDay(15, 0)).settings.bossModeHotkey == hotkey)
    }

    @Test("引导前也能改 (界面设置不依赖引导)")
    func worksBeforeOnboarding() throws {
        let hotkey = Hotkey(key: "9", modifiers: [.control, .shift])

        #expect(rejection(.setBossModeHotkey(hotkey), to: AppState()) == nil)
    }

    @Test(
        "macOS 15 不允许只用 ⌥ 或 ⌥⇧；单个修饰键会抢走 ⌘C、⌃A 这类常用键：都拦下",
        arguments: [
            Set<HotkeyModifier>(), [.option], [.option, .shift], [.shift], [.command], [.control],
        ]
    )
    func rejectsWeakModifiers(modifiers: Set<HotkeyModifier>) throws {
        let hotkey = Hotkey(key: "B", modifiers: modifiers)
        let error = rejection(.setBossModeHotkey(hotkey), to: try onboarded())

        #expect(error == .hotkeyModifiersInvalid)
        #expect(error?.message == "快捷键要按住两个以上修饰键，且包含 ⌃ 或 ⌘")
        #expect(Validation.hotkey(hotkey) == error)
    }

    @Test("至少两个修饰键且含 ⌃ 或 ⌘ 时可以保存", arguments: [
        Set<HotkeyModifier>([.control, .option]), [.command, .shift], [.control, .shift], [.command, .option], [.control, .option, .shift, .command],
    ])
    func acceptsStrongModifiers(modifiers: Set<HotkeyModifier>) throws {
        #expect(Validation.hotkey(Hotkey(key: "B", modifiers: modifiers)) == nil)
    }

    @Test("主键只能是单个大写字母或数字", arguments: ["", "b", "BB", "?", " ", "é"])
    func rejectsInvalidKey(key: String) throws {
        let error = rejection(.setBossModeHotkey(Hotkey(key: key, modifiers: [.control, .option])), to: try onboarded())

        #expect(error == .hotkeyKeyInvalid)
        #expect(error?.message == "主键只能是字母或数字")
    }

    @Test("校验失败时原快捷键不变")
    func rejectedKeepsOld() throws {
        let state = try onboarded()
        #expect(throws: CommandError.hotkeyModifiersInvalid) {
            try apply(.setBossModeHotkey(Hotkey(key: "B", modifiers: [.option])), to: state, at: standardDay(15, 0))
        }

        #expect(snapshot(of: state, at: standardDay(15, 0)).settings.bossModeHotkey.displayText == "⌃⌥B")
    }

    @Test("快捷键展示文案按 ⌃⌥⇧⌘ 顺序", arguments: [
        (Hotkey(key: "B", modifiers: [.control, .option]), "⌃⌥B"),
        (Hotkey(key: "K", modifiers: [.command, .shift]), "⇧⌘K"),
        (Hotkey(key: "1", modifiers: [.command, .shift, .option, .control]), "⌃⌥⇧⌘1"),
    ])
    func displayText(hotkey: Hotkey, text: String) {
        #expect(hotkey.displayText == text)
    }
}

@Suite("设置：开机自启与设置页初始值")
struct SettingsFormTests {
    @Test("开机自启开关保存在状态里")
    func launchAtLogin() throws {
        let off = try applied(.setLaunchAtLogin(false), to: try onboarded(), at: standardDay(15, 0))
        let on = try applied(.setLaunchAtLogin(true), to: off, at: standardDay(15, 0))

        #expect(snapshot(of: off, at: standardDay(15, 0)).settingsForm?.launchAtLogin == false)
        #expect(snapshot(of: on, at: standardDay(15, 0)).settingsForm?.launchAtLogin == true)
    }

    @Test("未完成引导时不能改开机自启，也没有设置页初始值")
    func requiresOnboarding() {
        #expect(rejection(.setLaunchAtLogin(false), to: AppState()) == .notOnboarded)
        #expect(snapshot(of: AppState(), at: standardDay(15, 0)).settingsForm == nil)
    }

    @Test("设置页初始值：当月月薪 (截掉末尾 0) 与今天生效的作息")
    func formValues() throws {
        let state = try applied(.changeSchedule(scheduleEnding(at: 19)), to: try onboarded(salary: Decimal(string: "20000.50")!), at: standardDay(15, 0))
        let form = try #require(snapshot(of: state, at: standardDay(15, 0)).settingsForm)

        #expect(form.monthlySalaryText == "20000.5")
        #expect(form.schedule == scheduleEnding(at: 19))
        #expect(form.launchAtLogin == true)
    }

    @Test("改月薪后设置页显示新月薪；下个月沿用")
    func formFollowsSalaryChange() throws {
        let state = try applied(.changeMonthlySalary(22000), to: try onboarded(), at: standardDay(15, 0))

        #expect(snapshot(of: state, at: standardDay(15, 0)).settingsForm?.monthlySalaryText == "22000")
        #expect(snapshot(of: state, at: moment(2026, 3, 2, 9, 0)).settingsForm?.monthlySalaryText == "22000")
    }
}
