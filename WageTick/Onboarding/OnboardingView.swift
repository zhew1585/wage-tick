import SwiftUI
import WageCore

/// 3 步引导：月薪 → 作息 (含午休) → 开机自启 (PRD 4.1.1、F1)。
/// 每一步点"下一步"时用核心的 `Validation` 校验，失败停留当前步并展示提示。
struct OnboardingView: View {
    let model: AppModel
    let onFinish: () -> Void

    @State private var step = Step.salary
    @State private var salaryText = ""
    @State private var scheduleDraft = ScheduleDraft(.default)
    @State private var launchAtLogin = true
    @State private var errorMessage: String?

    private enum Step: Int {
        case salary = 1, schedule, launch
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("第 \(step.rawValue) 步，共 3 步").font(.caption).foregroundStyle(Palette.muted)
            content
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Palette.loss)
            }
            Spacer(minLength: 0)
            buttons
        }
        .padding(24)
        .frame(width: 360, height: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .salary:
            Text("你的月薪是多少？").font(.title2.bold())
            Field("月薪", text: $salaryText, suffix: "元", size: .large)
                .onSubmit(next)
        case .schedule:
            Text("几点上下班？").font(.title2.bold())
            ScheduleFields(draft: $scheduleDraft)
        case .launch:
            Text("最后一步").font(.title2.bold())
            ToggleRow("开机自动启动", isOn: $launchAtLogin)
        }
    }

    private var buttons: some View {
        HStack(spacing: Spacing.s8) {
            if step != .salary {
                Button { move(to: Step(rawValue: step.rawValue - 1)!) } label: { Label("上一步", systemImage: "arrow.left") }
                    .buttonStyle(.secondary)
            }
            Button(step == .launch ? "开始搬砖" : "下一步", action: next)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primary(fullWidth: true))
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

    private var parsedSalary: Decimal? { SalaryText.parse(salaryText) }

    private var schedule: WorkSchedule { scheduleDraft.schedule }
}
