import SwiftUI
import WageCore

/// 3 步引导：月薪 → 作息 (含午休) → 开机自启 (PRD 4.1.1、F1)。
/// 每一步点"下一步"时用核心的 `Validation` 校验，失败停留当前步并展示提示。
struct OnboardingView: View {
    let model: AppModel
    let onFinish: () -> Void

    @State private var step = Step.salary
    @State private var salaryText = ""
    @State private var start = TimeOfDay.pickerDate(WorkSchedule.default.start)
    @State private var end = TimeOfDay.pickerDate(WorkSchedule.default.end)
    @State private var lunchEnabled = true
    @State private var lunchStart = TimeOfDay.pickerDate(LunchBreak.default.start)
    @State private var lunchEnd = TimeOfDay.pickerDate(LunchBreak.default.end)
    @State private var launchAtLogin = true
    @State private var errorMessage: String?

    private enum Step: Int {
        case salary = 1, schedule, launch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("第 \(step.rawValue) 步，共 3 步").font(.caption).foregroundStyle(.secondary)
            content
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(24)
        .frame(width: 360, height: 300)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .salary:
            Text("你的月薪是多少？").font(.title2.bold())
            TextField("月薪 (元)", text: $salaryText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(next)
        case .schedule:
            Text("几点上下班？").font(.title2.bold())
            Form {
                DatePicker("计划上班", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("计划下班", selection: $end, displayedComponents: .hourAndMinute)
                Toggle("午休", isOn: $lunchEnabled)
                if lunchEnabled {
                    DatePicker("午休开始", selection: $lunchStart, displayedComponents: .hourAndMinute)
                    DatePicker("午休结束", selection: $lunchEnd, displayedComponents: .hourAndMinute)
                }
            }
        case .launch:
            Text("最后一步").font(.title2.bold())
            Toggle("开机自动启动", isOn: $launchAtLogin)
        }
    }

    private var buttons: some View {
        HStack {
            if step != .salary {
                Button("上一步") { move(to: Step(rawValue: step.rawValue - 1)!) }
            }
            Spacer()
            Button(step == .launch ? "开始搬砖" : "下一步", action: next)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func next() {
        switch step {
        case .salary:
            if let error = Validation.monthlySalary(parsedSalary ?? 0) {
                errorMessage = error.message
            } else {
                move(to: .schedule)
            }
        case .schedule:
            if let error = Validation.schedule(schedule) {
                errorMessage = error.message
            } else {
                move(to: .launch)
            }
        case .launch:
            finish()
        }
    }

    private func finish() {
        let input = OnboardingInput(monthlySalary: parsedSalary ?? 0, schedule: schedule, launchAtLogin: launchAtLogin)
        do {
            try model.send(.completeOnboarding(input))
        } catch {
            errorMessage = error.message
            return
        }
        LaunchAtLogin.set(enabled: launchAtLogin)
        onFinish()
    }

    private func move(to step: Step) {
        errorMessage = nil
        self.step = step
    }

    /// 只接受最多 2 位小数的正数写法 (PRD 4.2.1)；其他写法视为未填。
    private var parsedSalary: Decimal? {
        let text = salaryText.trimmingCharacters(in: .whitespaces)
        guard text.wholeMatch(of: /[0-9]+(\.[0-9]{1,2})?/) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var schedule: WorkSchedule {
        WorkSchedule(
            start: TimeOfDay(pickerDate: start),
            end: TimeOfDay(pickerDate: end),
            lunch: lunchEnabled ? LunchBreak(start: TimeOfDay(pickerDate: lunchStart), end: TimeOfDay(pickerDate: lunchEnd)) : nil
        )
    }
}

/// 时间选择器用 `Date` 表示时刻，这里与核心的 `TimeOfDay` 互转。
private extension TimeOfDay {
    init(pickerDate: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: pickerDate)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    static func pickerDate(_ time: TimeOfDay) -> Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
    }
}
