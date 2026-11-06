import Foundation

/// 设置页打开时各项的初始值 (PRD F12)。显示模式与快捷键在 `Snapshot.settings` 里。
public struct SettingsForm: Sendable, Equatable {
    /// 当月月薪，截掉末尾 0，如「20000」「20000.5」，直接填进输入框。
    public let monthlySalaryText: String
    /// 设置页列表里展示的当月月薪，带 ¥，按金额格式，如「¥20000」「¥20000.50」。
    public let monthlySalaryDisplay: String
    /// 休息模式的当前选项，打开「休息模式」表单时预先选中；大小周按今天所在的周是大周还是小周。
    public let restModeChoice: RestModeChoice
    /// 设置页列表里展示的休息模式，如「双休」「单休」「大小周 · 这周休两天」，每周一大小周自然翻转。
    public var restModeText: String { restModeChoice.summary }
    /// 今天生效的作息。
    public let schedule: WorkSchedule
    public let launchAtLogin: Bool
    /// 显示模式各段下面的预览 (设计稿 P6 · 760)：此刻按该模式菜单栏会显示的数字。
    let menuBarPreviews: [MenuBarMode: String]

    /// 某个显示模式的预览，如金额「571.4286」、进度「57.14%」；不显示数字时 (仅图标、休息日) 为「—」。
    public func menuBarPreview(_ mode: MenuBarMode) -> String {
        menuBarPreviews[mode] ?? "—"
    }
}

extension SettingsForm {
    init(profile: Profile, today: Today, settings: InterfaceSettings) {
        let salary = profile.salary(for: today.date.yearMonth)
        monthlySalaryText = Format.editable(salary)
        monthlySalaryDisplay = Format.money(salary)
        restModeChoice = profile.restMode(for: today.date.yearMonth).choice(on: today.date)
        schedule = profile.schedule(on: today.date)
        launchAtLogin = profile.launchAtLogin
        menuBarPreviews = Dictionary(uniqueKeysWithValues: MenuBarMode.allCases.compactMap { mode in
            var preview = settings
            preview.menuBarMode = mode
            return MenuBarDisplay(today: today, settings: preview).text.map { (mode, $0) }
        })
    }
}
