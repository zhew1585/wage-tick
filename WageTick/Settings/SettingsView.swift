import SwiftUI
import WageCore

/// 设置页 (PRD F12，页面 P6)：月薪、作息、菜单栏显示模式、老板路过快捷键、开机自启。
/// 只管排版，动作与提示都在 `SettingsFormModel`。通知开关留给 #10。
struct SettingsView: View {
    @Bindable var form: SettingsFormModel

    var body: some View {
        Form {
            salarySection
            scheduleSection
            Section("菜单栏") {
                Picker("显示", selection: Binding(get: { form.menuBarMode }, set: { form.setMenuBarMode($0) })) {
                    ForEach(MenuBarMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            hotkeySection
            Section {
                Toggle("开机自动启动", isOn: Binding(get: { form.launchAtLogin }, set: { form.setLaunchAtLogin($0) }))
                messageRow(form.launchMessage)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 760)
    }

    private var salarySection: some View {
        Section {
            HStack {
                TextField("月薪 (元)", text: $form.salaryText)
                    .onSubmit { form.saveSalary() }
                Button("保存") { form.saveSalary() }
            }
            messageRow(form.salaryMessage)
        } header: {
            Text("月薪")
        } footer: {
            footnote("对当月整月生效，本月已经过去的日子也按新月薪算")
        }
    }

    private var scheduleSection: some View {
        Section {
            ScheduleFields(draft: $form.scheduleDraft)
            HStack {
                messageRow(form.scheduleMessage)
                Spacer()
                Button("保存") { form.saveSchedule() }
            }
        } header: {
            Text("作息")
        } footer: {
            footnote("从今天起生效，过去的日子保留当时的作息")
        }
    }

    private var hotkeySection: some View {
        Section {
            LabeledContent("老板路过快捷键") {
                Button(form.isRecordingHotkey ? "请按下新的快捷键…" : form.hotkeyText) {
                    if form.isRecordingHotkey {
                        form.endRecordingHotkey()
                    } else {
                        form.beginRecordingHotkey()
                    }
                }
                .monospacedDigit()
            }
            messageRow(form.hotkeyMessage)
        } footer: {
            footnote("至少按住两个修饰键，且包含 ⌃ 或 ⌘；录制时按 esc 取消")
        }
    }

    /// 分组页脚默认靠右，说明文字改成靠左。
    private func footnote(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func messageRow(_ message: FormMessage?) -> some View {
        switch message {
        case .saved: Text("已保存").font(.callout).foregroundStyle(.secondary)
        case .error(let text): Text(text).font(.callout).foregroundStyle(.red)
        case nil: EmptyView()
        }
    }
}
