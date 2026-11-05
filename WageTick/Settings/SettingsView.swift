import SwiftUI
import WageCore

/// 设置页 (PRD F12，设计稿 P6 设置 · 760)：钱与作息 (月薪、上下班、午休，点开弹表单改)，菜单栏 (显示模式与各模式预览、老板路过快捷键)，
/// 通知与启动 (下班通知、目标达成通知、开机自启)，系统拒绝通知时的提示条，数据 (清空数据并重启)。一屏放得下，放不下时滚动。
/// 只管排版，动作与提示都在 `SettingsFormModel`。
struct SettingsView: View {
    @Bindable var form: SettingsFormModel
    let close: () -> Void

    @State private var sheet: Sheet?
    @State private var confirmingReset = false

    private enum Sheet: Identifiable {
        case salary, schedule
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("设置", back: close)
            ScrollBody {
                VStack(alignment: .leading, spacing: Spacing.s22) {
                    moneySection
                    menuBarSection
                    notificationSection
                    if form.notificationDenied {
                        notificationWarning
                    }
                    dataSection
                }
                .padding(Spacing.screen)
            }
        }
        .frame(width: Spacing.pageWidth)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .salary: SalarySettingSheet(form: form, dismiss: { self.sheet = nil })
            case .schedule: ScheduleSettingSheet(form: form, dismiss: { self.sheet = nil })
            }
        }
    }

    // MARK: 钱与作息

    private var moneySection: some View {
        SettingsGroup("钱与作息") {
            CardBox {
                NavigationRow(title: "本月月薪", value: "¥\(form.savedSalaryText)", emphasized: true) {
                    form.beginEditingSalary()
                    sheet = .salary
                }
                CardDivider()
                NavigationRow(title: "上下班", value: form.schedule.workText, action: openSchedule)
                CardDivider()
                NavigationRow(title: "午休", value: form.schedule.lunchText, action: openSchedule)
            }
        }
    }

    private func openSchedule() {
        form.beginEditingSchedule()
        sheet = .schedule
    }

    // MARK: 菜单栏

    private var menuBarSection: some View {
        SettingsGroup("菜单栏") {
            CardBox {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    Text("显示模式").font(AppFont.body).foregroundStyle(Palette.ink)
                    ThemeSegmented(
                        options: MenuBarMode.allCases.map { .init(id: $0, title: $0.label, subtitle: form.menuBarPreviews[$0]) },
                        selection: form.menuBarMode,
                        select: form.setMenuBarMode
                    )
                }
                .padding(.horizontal, Spacing.s14)
                .padding(.vertical, Spacing.s12 - 1)
                CardDivider()
                hotkeyRow
            }
            message(form.hotkeyMessage)
        }
    }

    /// 老板路过快捷键：点按键帽开始录制，录制中再点或按 esc 取消。
    private var hotkeyRow: some View {
        HStack(spacing: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("老板路过").font(AppFont.body).foregroundStyle(Palette.ink)
                Text(form.isRecordingHotkey ? "至少按住两个修饰键，且包含 ⌃ 或 ⌘；esc 取消" : "一键隐藏数字，只剩小牛")
                    .font(AppFont.small)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: Spacing.s8)
            Button {
                if form.isRecordingHotkey {
                    form.endRecordingHotkey()
                } else {
                    form.beginRecordingHotkey()
                }
            } label: {
                if form.isRecordingHotkey {
                    Text("按下新组合…")
                        .font(AppFont.ui(11, .semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, Spacing.s8)
                        .frame(height: KeyCap.size)
                        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.r5))
                } else {
                    HStack(spacing: Spacing.s4) {
                        ForEach(Array(KeyCap.split(form.hotkeyText).enumerated()), id: \.offset) { _, key in
                            KeyCap(text: key)
                        }
                    }
                }
            }
            .buttonStyle(.highlight(radius: Radius.r5, outset: Spacing.s3))
            .help(form.isRecordingHotkey ? "取消录制" : "点一下录制新的快捷键")
        }
        .padding(.horizontal, Spacing.s14)
        .padding(.vertical, Spacing.s12 - 1)
    }

    // MARK: 通知与启动

    private var notificationSection: some View {
        SettingsGroup("通知与启动") {
            CardBox {
                toggle("下班通知", isOn: Binding(get: { form.offWorkNotification }, set: { form.setOffWorkNotification($0) }))
                CardDivider()
                toggle("目标达成通知", isOn: Binding(get: { form.goalReachedNotification }, set: { form.setGoalReachedNotification($0) }))
                CardDivider()
                toggle("开机自动启动", isOn: Binding(get: { form.launchAtLogin }, set: { form.setLaunchAtLogin($0) }))
            }
            message(form.launchMessage)
        }
    }

    // MARK: 数据

    /// 清空数据并重启：先弹确认，确认后重启回到引导 (测试流程用)。surface 底、loss 色字，高 40。
    private var dataSection: some View {
        SettingsGroup("数据") {
            Button(role: .destructive) { confirmingReset = true } label: {
                Text("清空数据并重启").frame(maxWidth: .infinity, minHeight: ControlHeight.wideButton)
            }
            .buttonStyle(.secondary(fullWidth: true))
            .alert("清空全部数据？", isPresented: $confirmingReset) {
                Button("清空并重启", role: .destructive, action: form.resetAndRelaunch)
                Button("取消", role: .cancel) {}
            } message: {
                Text("月薪、作息、扣钱、请假、白干和目标都会清掉，App 重启后从引导开始。上一份数据会留一份备份。")
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
        ToggleRow(title, isOn: isOn)
            .padding(.horizontal, Spacing.s14)
    }

    /// 系统拒绝了通知权限 (AC-SET-05)：点一下打开系统设置的通知页。
    private var notificationWarning: some View {
        Button(action: form.openNotificationSettings) {
            HStack(spacing: Spacing.s8) {
                PhosphorIcon(.bellSlash, size: 14)
                Text(NotificationCopy.permissionDenied).font(AppFont.ui(12, .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, Spacing.s12)
            .padding(.vertical, Spacing.s8 + 1)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: Radius.control))
        .help("打开系统设置")
    }

    /// 立即生效的设置被拒时的提示；成功不提示，开关、按键帽本身就是结果。
    @ViewBuilder
    private func message(_ message: FormMessage?) -> some View {
        if case .error(let text) = message {
            Text(text).font(AppFont.caption).foregroundStyle(Palette.loss)
        }
    }
}

/// 设置页的一组：11/600 muted 小标题 (字距 0.5)，下面是卡片。
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            GroupLabel(title: title, font: AppFont.ui(11, .semibold), tracking: 0.5)
            content()
        }
    }
}

/// 卡片里可点开的一行：左边名称，右边当前值 (12 号等宽) 与箭头；悬停、按下整行叠一层底，手型光标。
private struct NavigationRow: View {
    let title: String
    let value: String
    /// 值用 ink 色 (月薪)，否则 muted (时段)。
    var emphasized = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s4) {
                Text(title).font(AppFont.body).foregroundStyle(Palette.ink)
                Spacer(minLength: Spacing.s8)
                Text(value).font(AppFont.numCaption).foregroundStyle(emphasized ? Palette.ink : Palette.muted)
                PhosphorIcon(.caretRight, size: 12).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, Spacing.s14)
            .padding(.vertical, Spacing.s10 + 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: 0))
    }
}

/// 快捷键的一个按键帽 (24×24，surface 底、line 描边、圆角 5、11/600 等宽)。
private struct KeyCap: View {
    let text: String

    static let size: CGFloat = 24
    private static let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r5)
        Text(text)
            .font(AppFont.num(11, .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, Spacing.s6)
            .frame(minWidth: Self.size, minHeight: Self.size)
            .background(Palette.surface, in: shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
    }

    /// 「⌃⌥B」拆成一个个按键帽：修饰键各一个，剩下的主键一个 (主键可能不止一个字，如「F1」)。
    static func split(_ text: String) -> [String] {
        let mods = text.prefix { modifiers.contains($0) }.map(String.init)
        let key = String(text.dropFirst(mods.count))
        return key.isEmpty ? mods : mods + [key]
    }
}

/// 改当月月薪的表单 (PRD 4.2.1 #1)。
private struct SalarySettingSheet: View {
    @Bindable var form: SettingsFormModel
    let dismiss: () -> Void

    var body: some View {
        SettingSheet(title: "本月月薪", footnote: "对当月整月生效，本月已经过去的日子也按新月薪算", message: form.salaryMessage, save: save, dismiss: dismiss) {
            Field(nil, text: $form.salaryText, suffix: "元").onSubmit(save)
        }
    }

    private func save() {
        if form.saveSalary() { dismiss() }
    }
}

/// 改作息的表单 (PRD 4.2.3 #2)：上下班与午休。
private struct ScheduleSettingSheet: View {
    @Bindable var form: SettingsFormModel
    let dismiss: () -> Void

    var body: some View {
        SettingSheet(title: "作息", footnote: "从今天起生效，过去的日子保留当时的作息", message: form.scheduleMessage, save: save, dismiss: dismiss) {
            ScheduleFields(draft: $form.scheduleDraft)
        }
    }

    private func save() {
        if form.saveSchedule() { dismiss() }
    }
}

/// 设置表单的共同样子：标题、输入、说明、错误提示、取消与保存。
private struct SettingSheet<Content: View>: View {
    let title: String
    let footnote: String
    let message: FormMessage?
    let save: () -> Void
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s14) {
            Text(title).font(AppFont.sheetTitle).foregroundStyle(Palette.ink)
            content()
            Text(footnote).font(AppFont.caption).foregroundStyle(Palette.muted)
            if case .error(let text) = message {
                Text(text).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            HStack(spacing: Spacing.s8) {
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.secondary(fullWidth: true))
                Button(action: save) { Label("保存", systemImage: "checkmark") }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primary(fullWidth: true))
            }
        }
        .padding(Spacing.screen)
        .frame(width: 320)
        .background(Palette.bg)
    }
}

extension WorkSchedule {
    /// 设置页展示的上下班，如「10:00 – 18:00」。
    var workText: String { "\(start.clockText) – \(end.clockText)" }

    /// 设置页展示的午休，如「12:00 – 13:00」；不午休时「不午休」。
    var lunchText: String {
        guard let lunch else { return "不午休" }
        return "\(lunch.start.clockText) – \(lunch.end.clockText)"
    }
}

extension TimeOfDay {
    /// 时分，如「09:30」。
    var clockText: String { String(format: "%02d:%02d", hour, minute) }
}
