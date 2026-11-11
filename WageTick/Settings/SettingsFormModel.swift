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
/// 月薪、休息模式、作息在弹出的表单里改，点「保存」才生效；显示模式、隐藏 Dock 图标、桌面悬浮小牛、开机自启、两类通知开关改了立即生效。
@MainActor
@Observable
final class SettingsFormModel {
    /// 已保存的当月工资 (月薪或日薪)，截掉末尾 0，如「20000」「200」；打开工资表单时填进输入框。
    private(set) var savedSalaryText = ""
    /// 已保存的当月工资，如「月薪 ¥20000」「日薪 ¥200」；设置页「本月工资」一行展示。
    private(set) var savedSalaryDisplay = ""
    /// 已保存的当月工资按月还是按天；打开工资表单时预先选中。
    private(set) var savedPayBasis = PayBasis.monthly
    /// 工资表单里「月薪 | 日薪」的选择 (issue #16)。
    var payBasisDraft = PayBasis.monthly
    /// 已保存的发薪日，如「每月 15 号 · 遇休息日提前」，没设时「未设置」；设置页「发薪日」一行展示 (issue #20)。
    private(set) var savedPaydayText = ""
    /// 已保存的发薪日；打开发薪日表单时按它填好，没设时几号留空、默认提前。
    private(set) var savedPayday: Payday?
    /// 发薪日表单里的几号输入。
    var paydayDayText = ""
    /// 发薪日表单里「碰上不上班的日子」的选择。
    var paydayShiftDraft = PaydayShift.earlier
    /// 打开发薪日表单时的设置页快照，表单说明据此按编辑中的值推算本月实际发薪日。
    @ObservationIgnored private var paydayForm: SettingsForm?
    /// 已保存的休息模式，如「双休」「大小周 · 这周休两天」；设置页列表里展示。
    private(set) var savedRestModeText = ""
    /// 已保存的休息模式对应的选项 (大小周按今天所在的周)；打开休息模式表单时预先选中。
    private(set) var savedRestMode = RestModeChoice.twoDaysOff
    /// 休息模式表单里的选择。
    var restModeDraft = RestModeChoice.twoDaysOff
    /// 已保存的作息 (今天生效的)；设置页列表里展示。
    private(set) var schedule = WorkSchedule.default
    /// 工资表单里的输入，打开表单时按已保存的填好。
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
    /// 桌面悬浮小牛开关 (issue #21)。
    private(set) var showsFloatingCow = true
    /// 设了发薪日：菜单栏一组才出现「桌面悬浮小牛」开关，改完发薪日立即出现。
    var hasPayday: Bool { savedPayday != nil }
    /// 系统拒绝了通知权限：通知区显示提示 (AC-SET-05)。
    private(set) var notificationDenied = false

    private(set) var salaryMessage: FormMessage?
    private(set) var paydayMessage: FormMessage?
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
            updateSalary(from: form)
            updateRestMode(from: form)
            updatePayday(from: form)
            schedule = form.schedule
            launchAtLogin = form.launchAtLogin
        }
        menuBarMode = snap.settings.menuBarMode
        updatePreviews(from: snap)
        offWorkNotification = snap.settings.offWorkNotification
        goalReachedNotification = snap.settings.goalReachedNotification
        hidesDockIcon = snap.settings.hidesDockIcon
        showsFloatingCow = snap.settings.showsFloatingCow
        refreshNotificationPermission()
        salaryMessage = nil
        paydayMessage = nil
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
        // 右键菜单里「关掉悬浮小牛」也会改它，设置页开着时跟上。
        showsFloatingCow = snap.settings.showsFloatingCow
        menuBarPreviews = Dictionary(uniqueKeysWithValues: MenuBarMode.allCases.map { ($0, form.menuBarPreview($0)) })
    }

    /// 打开工资表单：按已保存的金额与月薪 / 日薪填好，清掉上次的提示。
    func beginEditingSalary() {
        salaryText = savedSalaryText
        payBasisDraft = savedPayBasis
        salaryMessage = nil
    }

    /// 打开发薪日表单：按已保存的填好 (没设时几号留空、默认提前)，清掉上次的提示。
    func beginEditingPayday() {
        paydayDayText = savedPayday.map { "\($0.dayOfMonth)" } ?? ""
        paydayShiftDraft = savedPayday?.shift ?? .earlier
        paydayForm = model.currentSnapshot().settingsForm
        paydayMessage = nil
    }

    /// 发薪日表单正在编辑的值；几号不是数字时按 0，保存时由核心报「发薪日填 1 到 31 号」。
    private var paydayDraft: Payday {
        Payday(dayOfMonth: Int(paydayDayText.trimmingCharacters(in: .whitespaces)) ?? 0, shift: paydayShiftDraft)
    }

    /// 发薪日表单下方的说明，按编辑中的值写出本月实际哪天发，见 `SettingsForm.paydayNote`。
    var paydayNote: String {
        paydayForm?.paydayNote(for: paydayDraft) ?? ""
    }

    /// 改发薪日，全局一份。返回是否保存成功。
    func savePayday() -> Bool {
        paydayMessage = send(.setPayday(paydayDraft))
        guard paydayMessage == .saved else { return false }
        if let form = model.currentSnapshot().settingsForm {
            updatePayday(from: form)
        }
        return true
    }

    private func updatePayday(from form: SettingsForm) {
        savedPayday = form.payday
        savedPaydayText = form.paydayText
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

    /// 改工资 (月薪或日薪)，对当月整月生效。输入不是数字时按 0 交给核心，得到「月薪得是个正数」或「日薪得是个正数」。
    /// 返回是否保存成功。
    func saveSalary() -> Bool {
        salaryMessage = send(.changeSalary(SalaryText.parse(salaryText) ?? 0, basis: payBasisDraft))
        guard salaryMessage == .saved else { return false }
        if let form = model.currentSnapshot().settingsForm {
            updateSalary(from: form)
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

    private func updateSalary(from form: SettingsForm) {
        savedSalaryText = form.salaryText
        savedSalaryDisplay = form.salaryDisplay
        savedPayBasis = form.payBasis
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

    /// 记进状态，菜单栏随即刷新，浮窗跟着出现或收起。
    func setShowsFloatingCow(_ shown: Bool) {
        guard send(.setShowsFloatingCow(shown)) == .saved else { return }
        showsFloatingCow = shown
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
