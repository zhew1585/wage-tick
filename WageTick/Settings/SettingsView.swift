import SwiftUI
import WageCore

/// 设置页 (PRD F12，大胆版设计稿「设置」)：橙色头图「你现在的身价」，大数字是本月工资，下面一行「月薪 · 双休 · 10:00–18:00」，
/// 小牛端着咖啡说「该涨了」；往下滑头图收成窄栏。头图下面按组排成墨色细描边的圆角卡片：
/// 钱与作息 (本月工资、发薪日、休息模式、作息，点开弹表单改)，菜单栏 (显示模式三选一、桌面悬浮小牛、隐藏 Dock 图标)，
/// 通知与启动 (下班通知、目标达成通知、开机自启)，系统拒绝通知时的提示条，更新 (版本、自动更新、接收尝鲜版、检查更新)，数据 (清空数据并重启)。
/// 只管排版，动作与提示都在 `SettingsFormModel`；返回即关窗 (`close`)。
struct SettingsView: View {
    @Bindable var form: SettingsFormModel
    let updater: AppUpdater
    var close: () -> Void = {}

    @State private var sheet: Sheet?
    @State private var confirmingReset = false

    private enum Sheet: Identifiable {
        case salary, payday, restMode, schedule
        var id: Self { self }
    }

    var body: some View {
        HeroScroll { collapse in
            hero(collapse)
        } content: {
            VStack(alignment: .leading, spacing: Spacing.s24) {
                moneySection
                menuBarSection
                notificationSection
                if form.notificationDenied {
                    notificationWarning
                }
                updateSection
                dataSection
            }
            .padding(EdgeInsets(top: Spacing.s24, leading: Spacing.screen, bottom: Spacing.s24, trailing: Spacing.screen))
        }
        .frame(width: Spacing.pageWidth)
        .background(Palette.bg)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .salary: SalarySettingSheet(form: form, dismiss: { self.sheet = nil })
            case .payday: PaydaySettingSheet(form: form, dismiss: { self.sheet = nil })
            case .restMode: RestModeSettingSheet(form: form, dismiss: { self.sheet = nil })
            case .schedule: ScheduleSettingSheet(form: form, dismiss: { self.sheet = nil })
            }
        }
    }

    private func hero(_ collapse: CGFloat) -> some View {
        BoldHero(
            theme: .orange,
            back: HeroBack(label: "返回", action: close),
            kicker: "你现在的身价",
            caption: form.heroSummary,
            captionIcon: .calendarBlank,
            cow: .pose(.working),
            bubble: HeroBubbleContent(value: "该涨了", numeric: false),
            collapse: collapse,
            compactValue: form.heroAmount
        ) {
            HeroAmount(text: form.heroAmount, theme: .orange, maxWidth: 230)
        }
    }

    // MARK: 钱与作息

    private var moneySection: some View {
        SettingsGroup("钱与作息") {
            InkCard {
                SettingsNavigationRow(title: "本月工资", value: form.savedSalaryDisplay, emphasized: true) {
                    form.beginEditingSalary()
                    sheet = .salary
                }
                InkCardDivider()
                SettingsNavigationRow(title: "发薪日", value: form.savedPaydayText) {
                    form.beginEditingPayday()
                    sheet = .payday
                }
                InkCardDivider()
                SettingsNavigationRow(title: "休息模式", value: form.savedRestModeText) {
                    form.beginEditingRestMode()
                    sheet = .restMode
                }
                InkCardDivider()
                SettingsNavigationRow(title: "作息", value: form.schedule.summaryText) {
                    form.beginEditingSchedule()
                    sheet = .schedule
                }
            }
        }
    }

    // MARK: 菜单栏

    private var menuBarSection: some View {
        SettingsGroup("菜单栏") {
            InkCard {
                VStack(alignment: .leading, spacing: Spacing.s10) {
                    Text("显示模式").font(AppFont.ui(14)).foregroundStyle(Palette.ink)
                    MenuBarModeTiles(previews: form.menuBarPreviews, selection: form.menuBarMode, select: form.setMenuBarMode)
                }
                .padding(EdgeInsets(top: Spacing.s14, leading: Spacing.s14, bottom: Spacing.s14, trailing: Spacing.s14))
                InkCardDivider()
                toggle("桌面悬浮小牛", isOn: Binding(get: { form.showsFloatingCow }, set: { form.setShowsFloatingCow($0) }))
                InkCardDivider()
                toggle("隐藏 Dock 图标", isOn: Binding(get: { form.hidesDockIcon }, set: { form.setHidesDockIcon($0) }))
            }
        }
    }

    // MARK: 通知与启动

    private var notificationSection: some View {
        SettingsGroup("通知与启动") {
            InkCard {
                toggle("下班通知", isOn: Binding(get: { form.offWorkNotification }, set: { form.setOffWorkNotification($0) }))
                InkCardDivider()
                toggle("目标达成通知", isOn: Binding(get: { form.goalReachedNotification }, set: { form.setGoalReachedNotification($0) }))
                InkCardDivider()
                toggle("开机自动启动", isOn: Binding(get: { form.launchAtLogin }, set: { form.setLaunchAtLogin($0) }))
            }
            message(form.launchMessage)
        }
    }

    // MARK: 更新

    /// 版本与更新 (ADR-0007)：当前版本、自动更新与接收尝鲜版 (nightly) 开关、检查更新按钮。开发版不检查更新，全部置灰。
    private var updateSection: some View {
        SettingsGroup("更新") {
            InkCard {
                HStack {
                    Text("当前版本").font(AppFont.ui(14)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text(updater.isEnabled ? updater.versionText : "开发版").font(AppFont.num(13)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, Spacing.s14)
                .padding(.vertical, Spacing.s12)
                InkCardDivider()
                toggle("自动更新", isOn: Binding(get: { updater.automaticallyUpdates }, set: { updater.setAutomaticallyUpdates($0) }))
                    .disabled(!updater.isEnabled)
                InkCardDivider()
                toggle("接收尝鲜版", isOn: Binding(get: { updater.receivesNightly }, set: { updater.setReceivesNightly($0) }))
                    .disabled(!updater.isEnabled)
            }
            Button(action: updater.checkForUpdates) {
                Label { Text("检查更新") } icon: { PhosphorIcon(.arrowClockwise) }
            }
            .buttonStyle(.pill(.outline))
            .disabled(!updater.isEnabled)
        }
    }

    // MARK: 数据

    /// 清空数据并重启：先弹确认，确认后重启回到引导 (测试流程用)。浅底红字的胶囊。
    private var dataSection: some View {
        SettingsGroup("数据") {
            Button(role: .destructive) { confirmingReset = true } label: {
                Text("清空数据并重启")
            }
            .buttonStyle(DangerPillButtonStyle())
            .alert("清空全部数据？", isPresented: $confirmingReset) {
                Button("清空并重启", role: .destructive, action: form.resetAndRelaunch)
                Button("取消", role: .cancel) {}
            } message: {
                Text("月薪、作息、扣钱、请假、白干和目标都会清掉，App 重启后从引导开始。上一份数据会留一份备份。")
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.ink)
            .padding(.horizontal, Spacing.s14)
    }

    /// 系统拒绝了通知权限 (AC-SET-05)：点一下打开系统设置的通知页。
    private var notificationWarning: some View {
        Button(action: form.openNotificationSettings) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                PhosphorIcon(.bellSlash, size: 14).iconOnTextBaseline(12)
                Text(NotificationCopy.permissionDenied).font(AppFont.ui(12, .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, Spacing.s14)
            .padding(.vertical, Spacing.s10)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.r14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: Radius.r14))
        .help("打开系统设置")
    }

    /// 立即生效的设置被拒时的提示；成功不提示，开关本身就是结果。
    @ViewBuilder
    private func message(_ message: FormMessage?) -> some View {
        if case .error(let text) = message {
            Text(text).font(AppFont.caption).foregroundStyle(Palette.loss)
        }
    }
}

extension WorkSchedule {
    /// 设置页展示的上下班，如「10:00 – 18:00」。
    var workText: String { "\(start.clockText) – \(end.clockText)" }

    /// 设置页展示的饭点，如「饭点 12:00 – 13:00」；没有饭点时「没有饭点」。
    var lunchText: String {
        guard let lunch else { return "没有饭点" }
        return "饭点 \(lunch.start.clockText) – \(lunch.end.clockText)"
    }

    /// 设置页「作息」一行右侧的两行：上下班，换行后饭点。
    var summaryText: String { "\(workText)\n\(lunchText)" }
}

extension TimeOfDay {
    /// 时分，如「09:30」。
    var clockText: String { String(format: "%02d:%02d", hour, minute) }
}
