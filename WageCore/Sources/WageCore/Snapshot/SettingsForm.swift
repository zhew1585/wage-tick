import Foundation

/// 设置页打开时各项的初始值 (PRD F12)。显示模式与快捷键在 `Snapshot.settings` 里。
public struct SettingsForm: Sendable, Equatable {
    /// 当月工资 (月薪或日薪)，截掉末尾 0，如「20000」「20000.5」「200」，直接填进输入框。
    public let salaryText: String
    /// 设置页「本月工资」一行展示的值，如「月薪 ¥20000」「日薪 ¥200」。
    public let salaryDisplay: String
    /// 当月工资按月还是按天，改工资表单据此预先选中。
    public let payBasis: PayBasis
    /// 设置页头图的大数字：当月工资金额，如「¥20000」「¥200」(大胆版设计稿「设置」)。
    public let salaryAmount: String
    /// 休息模式的当前选项，打开「休息模式」表单时预先选中；大小周按今天所在的周是大周还是小周。
    public let restModeChoice: RestModeChoice
    /// 设置页列表里展示的休息模式，如「双休」「单休」「大小周 · 这周休两天」，每周一大小周自然翻转。
    public var restModeText: String { restModeChoice.summary }
    /// 设置页头图大数字下面的一行，如「月薪 · 双休 · 10:00–18:00」：按月还是按天、休息模式、今天生效的上下班。
    public var summary: String {
        "\(payBasis.label) · \(restModeChoice.title) · \(Format.clock(schedule.start))–\(Format.clock(schedule.end))"
    }
    /// 今天生效的作息。
    public let schedule: WorkSchedule
    public let launchAtLogin: Bool
    /// 发薪日 (issue #20)，打开发薪日表单时预填；没设时为 nil。
    public let payday: Payday?
    /// 设置页「发薪日」一行的值，如「每月 15 号 · 遇休息日提前」，没设时为「未设置」。
    public var paydayText: String { payday?.summary ?? "未设置" }
    /// 发薪日表单的说明据此推算本月实际发薪日：今天所在的月与应出勤判定。
    let month: YearMonth
    let rule: AttendanceRule
    /// 显示模式各段下面的预览 (设计稿 P6 · 760)：此刻按该模式菜单栏会显示的数字。
    let menuBarPreviews: [MenuBarMode: String]

    /// 某个显示模式的预览，如金额「571.4286」、进度「57.14%」；不显示数字时 (仅图标、休息日) 为「—」。
    public func menuBarPreview(_ mode: MenuBarMode) -> String {
        menuBarPreviews[mode] ?? "—"
    }
}

extension SettingsForm {
    init(profile: Profile, today: Today, settings: InterfaceSettings, holidays: HolidayTable) {
        let pay = profile.pay(for: today.date.yearMonth)
        salaryText = Format.editable(pay.amount)
        salaryDisplay = "\(pay.basis.label) \(Format.money(pay.amount))"
        payBasis = pay.basis
        salaryAmount = Format.money(pay.amount)
        restModeChoice = profile.restMode(for: today.date.yearMonth).choice(on: today.date)
        schedule = profile.schedule(on: today.date)
        launchAtLogin = profile.launchAtLogin
        payday = profile.payday
        month = today.date.yearMonth
        rule = AttendanceRule(holidays: holidays)
        menuBarPreviews = Dictionary(uniqueKeysWithValues: MenuBarMode.allCases.compactMap { mode in
            var preview = settings
            preview.menuBarMode = mode
            return MenuBarDisplay(today: today, settings: preview).text.map { (mode, $0) }
        })
    }
}

extension SettingsForm {
    /// 发薪日表单下方的说明 (设计稿 QgdwY)：先说月末规则，再按编辑中的发薪日写出这个月实际哪天发，如
    /// 「填 29 到 31 时，小月按月末那天算。这个月 15 号是周日，会提前到 13 号 (周五) 发。」
    /// 几号不在 1 至 31 时只说规则 (保存时由 `.setPayday` 报错)。
    public func paydayNote(for payday: Payday) -> String {
        let monthEndRule = "填 29 到 31 时，小月按月末那天算。"
        guard Payday.validDays.contains(payday.dayOfMonth) else { return monthEndRule }
        let days = month.days
        let nominal = days[min(payday.dayOfMonth, days.count) - 1]
        let actual = rule.actualPayday(in: month, payday: payday)
        let which = payday.dayOfMonth > days.count
            ? "这个月按月末 \(nominal.day) 号 (\(Format.weekday(nominal))) 算"
            : "这个月 \(nominal.day) 号是\(Format.weekday(nominal))"
        return monthEndRule + which + shiftClause(nominal: nominal, actual: actual, shift: payday.shift) + "。"
    }

    /// 那天要不要挪：要上班「当天发」；不挪「照常当天发」；挪了「会提前到 13 号 (周五) 发」，跨月时带月份。
    /// 星期本身说明不了为什么不上班 (如工作日放假) 时先补一句「不上班」。
    private func shiftClause(nominal: LocalDate, actual: LocalDate, shift: PaydayShift) -> String {
        guard !rule.isAttendanceDay(nominal) else { return "，当天发" }
        let reason = rule.holidays.restMode(for: month).isRestDay(nominal) ? "" : "，不上班"
        guard actual != nominal else { return reason + "，照常当天发" }
        let verb = shift == .later ? "顺延" : "提前"
        let monthPart = actual.yearMonth == month ? "" : "\(actual.month) 月 "
        return reason + "，会\(verb)到 \(monthPart)\(actual.day) 号 (\(Format.weekday(actual))) 发"
    }
}
