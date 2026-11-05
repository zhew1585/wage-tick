import Foundation

/// 设置页打开时各项的初始值 (PRD F12)。显示模式与快捷键在 `Snapshot.settings` 里。
public struct SettingsForm: Sendable, Equatable {
    /// 当月月薪，截掉末尾 0，如「20000」「20000.5」，直接填进输入框。
    public let monthlySalaryText: String
    /// 今天生效的作息。
    public let schedule: WorkSchedule
    public let launchAtLogin: Bool
    /// 显示模式各段下面的预览 (设计稿 P6 · 760)：此刻按该模式菜单栏会显示的数字，不看老板路过。
    let menuBarPreviews: [MenuBarMode: String]

    /// 某个显示模式的预览，如金额「571.4286」、进度「57.14%」；不显示数字时 (仅图标、休息日) 为「—」。
    public func menuBarPreview(_ mode: MenuBarMode) -> String {
        menuBarPreviews[mode] ?? "—"
    }
}

extension SettingsForm {
    init(profile: Profile, today: Today, settings: InterfaceSettings) {
        monthlySalaryText = Format.trimmed(profile.salary(for: today.date.yearMonth))
        schedule = profile.schedule(on: today.date)
        launchAtLogin = profile.launchAtLogin
        var plain = settings
        plain.bossMode = false
        menuBarPreviews = Dictionary(uniqueKeysWithValues: MenuBarMode.allCases.compactMap { mode in
            plain.menuBarMode = mode
            return MenuBarDisplay(today: today, settings: plain).text.map { (mode, $0) }
        })
    }
}
