import Foundation

/// 设置页打开时各项的初始值 (PRD F12)。显示模式与快捷键在 `Snapshot.settings` 里。
public struct SettingsForm: Sendable, Equatable {
    /// 当月月薪，截掉末尾 0，如「20000」「20000.5」，直接填进输入框。
    public let monthlySalaryText: String
    /// 今天生效的作息。
    public let schedule: WorkSchedule
    public let launchAtLogin: Bool
}

extension SettingsForm {
    init(profile: Profile, today: LocalDate) {
        monthlySalaryText = Format.trimmed(profile.salary(for: today.yearMonth))
        schedule = profile.schedule(on: today)
        launchAtLogin = profile.launchAtLogin
    }
}
