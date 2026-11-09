import Foundation
import Observation
import WageCore

/// 设置页某一项操作后的提示。
enum FormMessage: Equatable {
    case saved
    case error(String)
}

/// 设置页的表单状态与动作 (PRD F12)。
/// 每一项都发命令给核心，校验与提示文案来自核心的 `CommandError`，与引导一致 (PRD 4.3.5 #1 至 #3)。
/// 月薪、休息模式、作息在弹出的表单里改，点「保存」才生效；显示模式、隐藏 Dock 图标、开机自启、两类通知开关改了立即生效。
@MainActor
@Observable
final class SettingsFormModel {
    /// 已保存的当月月薪，截掉末尾 0，如「20000」；打开月薪表单时填进输入框。
    private(set) var savedSalaryText = ""
    /// 已保存的当月月薪，带 ¥、按金额格式，如「¥20000.50」；设置页列表里展示。
    private(set) var savedSalaryDisplay = ""
    /// 已保存的休息模式，如「双休」「大小周 · 这周休两天」；设置页列表里展示。
    private(set) var savedRestModeText = ""
    /// 已保存的休息模式对应的选项 (大小周按今天所在的周)；打开休息模式表单时预先选中。
    private(set) var savedRestMode = RestModeChoice.twoDaysOff
    /// 休息模式表单里的选择。
    var restModeDraft = RestModeChoice.twoDaysOff
    /// 已保存的作息 (今天生效的)；设置页列表里展示。
    private(set) var schedule = WorkSchedule.default
    /// 月薪表单里的输入，打开表单时按已保存的填好。
    var salaryText = ""
    /// 作息表单里的草稿，打开表单时按已保存的填好。
    var scheduleDraft = ScheduleDraft(.default)
    private(set) var menuBarMode = MenuBarMode.amount
    /// 显示模式各段下面的预览 (此刻菜单栏会显示的数字，如「571.4286」「57.14%」「—」)，打开设置页期间每秒刷新。
    private(set) var menuBarPreviews: [MenuBarMode: String] = [:]
    private(set) var launchAtLogin = true
    private(set) var offWorkNotification = true
    private(set) var goalReachedNotification = true
    private(set) var hidesDockIcon = false
    /// 系统拒绝了通知权限：通知区显示提示 (AC-SET-05)。
    private(set) var notificationDenied = false

    private(set) var salaryMessage: FormMessage?
    private(set) var restModeMessage: FormMessage?
    private(set) var scheduleMessage: FormMessage?
    private(set) var launchMessage: FormMessage?

    @ObservationIgnored private let model: AppModel
    /// 改完设置立即重绘菜单栏。
    @ObservationIgnored private weak var menuBar: StatusItemController?
    @ObservationIgnored private let notifier: SystemNotifier

    /// `menuBar` 为 nil 时 (离屏预览) 改了设置不重绘菜单栏。
    init(model: AppModel, menuBar: StatusItemController?, notifier: SystemNotifier) {
        self.model = model
        self.menuBar = menuBar
        self.notifier = notifier
    }

    /// 清空数据并重启：状态文件挪成备份 (`state.before-reset.json`)，清掉偏好 (窗口位置、钉住)，重启后从引导开始。
    /// 节假日缓存与系统登录项不动。
    func resetAndRelaunch() {
        model.resetAllData()
        UserDefaults.standard.removePersistentDomain(forName: AppIdentity.bundleID)
        AppRelaunch.relaunch()
    }

    /// 打开设置页时按最新快照填好各项，清掉上次的提示。
    func reload() {
        let snap = model.currentSnapshot()
        if let form = snap.settingsForm {
            savedSalaryText = form.monthlySalaryText
            savedSalaryDisplay = form.monthlySalaryDisplay
            updateRestMode(from: form)
            schedule = form.schedule
            launchAtLogin = form.launchAtLogin
        }
        menuBarMode = snap.settings.menuBarMode
        updatePreviews(from: snap)
        offWorkNotification = snap.settings.offWorkNotification
        goalReachedNotification = snap.settings.goalReachedNotification
        hidesDockIcon = snap.settings.hidesDockIcon
        refreshNotificationPermission()
        salaryMessage = nil
        restModeMessage = nil
        scheduleMessage = nil
        launchMessage = nil
    }

    /// 按最新快照刷新显示模式预览，设置窗口可见时每秒调一次。
    func refreshMenuBarPreviews() {
        updatePreviews(from: model.currentSnapshot())
    }

    private func updatePreviews(from snap: Snapshot) {
        guard let form = snap.settingsForm else { return }
        menuBarPreviews = Dictionary(uniqueKeysWithValues: MenuBarMode.allCases.map { ($0, form.menuBarPreview($0)) })
    }

    /// 打开月薪表单：按已保存的填好，清掉上次的提示。
    func beginEditingSalary() {
        salaryText = savedSalaryText
        salaryMessage = nil
    }

    /// 打开休息模式表单：预先选中已保存的，清掉上次的提示。
    func beginEditingRestMode() {
        restModeDraft = savedRestMode
        restModeMessage = nil
    }

    /// 打开作息表单：按已保存的填好，清掉上次的提示。
    func beginEditingSchedule() {
        scheduleDraft = ScheduleDraft(schedule)
        scheduleMessage = nil
    }

    /// 改月薪，对当月整月生效。输入不是数字时按 0 交给核心，得到「月薪得是个正数」。返回是否保存成功。
    func saveSalary() -> Bool {
        salaryMessage = send(.changeMonthlySalary(SalaryText.parse(salaryText) ?? 0))
        guard salaryMessage == .saved else { return false }
        if let form = model.currentSnapshot().settingsForm {
            savedSalaryText = form.monthlySalaryText
            savedSalaryDisplay = form.monthlySalaryDisplay
        }
        return true
    }

    /// 改休息模式，与月薪一样对当月整月生效。返回是否保存成功。
    func saveRestMode() -> Bool {
        restModeMessage = send(.changeRestMode(restModeDraft))
        guard restModeMessage == .saved else { return false }
        if let form = model.currentSnapshot().settingsForm {
            updateRestMode(from: form)
        }
        return true
    }

    private func updateRestMode(from form: SettingsForm) {
        savedRestMode = form.restModeChoice
        savedRestModeText = form.restModeText
    }

    /// 改作息，从今天起生效。返回是否保存成功。
    func saveSchedule() -> Bool {
        scheduleMessage = send(.changeSchedule(scheduleDraft.schedule))
        guard scheduleMessage == .saved else { return false }
        if let form = model.currentSnapshot().settingsForm {
            schedule = form.schedule
        }
        return true
    }

    func setMenuBarMode(_ mode: MenuBarMode) {
        guard send(.setMenuBarMode(mode)) == .saved else { return }
        menuBarMode = mode
    }

    /// 先改系统登录项，成功了才记进状态，免得开关与系统实际不一致。
    func setLaunchAtLogin(_ enabled: Bool) {
        guard LaunchAtLogin.set(enabled: enabled) else {
            launchMessage = .error("开机自启没设置成功，去系统设置的登录项里看看")
            return
        }
        launchMessage = send(.setLaunchAtLogin(enabled))
        if launchMessage == .saved { launchAtLogin = enabled }
    }

    func setOffWorkNotification(_ enabled: Bool) {
        guard send(.setOffWorkNotification(enabled)) == .saved else { return }
        offWorkNotification = enabled
    }

    func setGoalReachedNotification(_ enabled: Bool) {
        guard send(.setGoalReachedNotification(enabled)) == .saved else { return }
        goalReachedNotification = enabled
    }

    /// 记进状态后立即切换 Dock 图标。
    func setHidesDockIcon(_ hidden: Bool) {
        guard send(.setHidesDockIcon(hidden)) == .saved else { return }
        hidesDockIcon = hidden
        DockIcon.apply(hidden: hidden)
    }

    func openNotificationSettings() {
        notifier.openSystemSettings()
    }

    /// 重新读一次系统通知权限：打开设置页、从系统设置切回来时调用。
    func refreshNotificationPermission() {
        Task { notificationDenied = await notifier.isDenied() }
    }

    /// 发命令并立即重绘菜单栏，返回要展示的提示。
    private func send(_ command: Command) -> FormMessage {
        do {
            try model.send(command)
        } catch {
            return .error(error.message)
        }
        menuBar?.refresh()
        return .saved
    }
}
