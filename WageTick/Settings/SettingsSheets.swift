import SwiftUI
import WageCore

/// 改当月工资的表单 (PRD 4.2.1 #1)：「月薪 | 日薪」小切换 + 金额 (单位跟着变)，设计稿「按天算工资」⑥。
struct SalarySettingSheet: View {
    @Bindable var form: SettingsFormModel
    let dismiss: () -> Void

    var body: some View {
        SettingSheet(title: "本月工资", footnote: footnote, message: form.salaryMessage, save: save, dismiss: dismiss) {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                PayBasisSwitch(selection: form.payBasisDraft) { form.payBasisDraft = $0 }
                Field(nil, text: $form.salaryText, suffix: form.payBasisDraft.unit).onSubmit(save)
            }
        }
    }

    private var footnote: String {
        switch form.payBasisDraft {
        case .monthly: "对当月整月生效，本月已经过去的日子也按新月薪算"
        case .daily: "对本月整月生效。按天算时只有要上班的日子有钱，周末和法定节假日都是 0"
        }
    }

    private func save() {
        if form.saveSalary() { dismiss() }
    }
}

/// 改发薪日的表单 (issue #20，设计稿 QgdwY)：每月几号 + 碰上不上班的日子怎么挪，说明里写出本月实际哪天发。
struct PaydaySettingSheet: View {
    @Bindable var form: SettingsFormModel
    let dismiss: () -> Void

    var body: some View {
        SettingSheet(title: "发薪日", footnote: form.paydayNote, message: form.paydayMessage, save: save, dismiss: dismiss) {
            Field("每月几号发", text: $form.paydayDayText, suffix: "号").onSubmit(save)
            VStack(alignment: .leading, spacing: Spacing.s6) {
                Text("碰上不上班的日子").font(AppFont.label).foregroundStyle(Palette.muted)
                PaydayShiftSwitch(selection: form.paydayShiftDraft) { form.paydayShiftDraft = $0 }
            }
        }
    }

    private func save() {
        if form.savePayday() { dismiss() }
    }
}

/// 改休息模式的表单 (PRD 4.2.2)：四选一，预先选中当前的；对本月整月生效。
struct RestModeSettingSheet: View {
    @Bindable var form: SettingsFormModel
    let dismiss: () -> Void

    var body: some View {
        SettingSheet(title: "休息模式", footnote: "对本月整月生效，本月日薪跟着重算", message: form.restModeMessage, save: save, dismiss: dismiss) {
            RestModePicker(selection: form.restModeDraft) { form.restModeDraft = $0 }
        }
    }

    private func save() {
        if form.saveRestMode() { dismiss() }
    }
}

/// 改作息的表单 (PRD 4.2.3 #2)：上下班与饭点。
struct ScheduleSettingSheet: View {
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

/// 设置表单的共同样子：标题、输入、说明、错误提示，底部「取消」描边胶囊与「保存」墨色胶囊。
private struct SettingSheet<Content: View>: View {
    let title: String
    let footnote: String
    let message: FormMessage?
    let save: () -> Void
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s14) {
            Text(title).font(AppFont.fun(22)).foregroundStyle(Palette.ink)
            content()
            Text(footnote).font(AppFont.caption).foregroundStyle(Palette.muted)
            if case .error(let text) = message {
                Text(text).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            HStack(spacing: Spacing.s10) {
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.pill(.outline))
                Button(action: save) { Label { Text("保存") } icon: { PhosphorIcon(.check) } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.pill(.ink))
            }
            .padding(.top, Spacing.s4)
        }
        .padding(Spacing.screen)
        .frame(width: 320)
        .background(Palette.bg)
    }
}
