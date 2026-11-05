import SwiftUI
import WageCore

/// 3 步引导：月薪 → 作息 (含午休) → 开机自启 (PRD 4.1.1、F1；设计稿 P1 引导 · 1 至 3)。
/// 顶部步骤条，中间是当前步，底部「上一步」与「下一步 / 开始搬砖」。
/// 每一步点"下一步"时用核心的 `Validation` 校验，失败停留当前步并展示提示。
struct OnboardingView: View {
    /// 窗口内容尺寸 (设计稿 360×560)。
    static let size = CGSize(width: 360, height: 560)

    let model: AppModel
    let onFinish: () -> Void

    @State private var step: OnboardingStep
    @State private var salaryText: String
    @State private var scheduleDraft = ScheduleDraft(.default)
    @State private var launchAtLogin = true
    @State private var errorMessage: String?

    /// `step`、`salaryText` 只在离屏截图时指定，App 里从第 1 步、空月薪开始。
    init(model: AppModel, step: OnboardingStep = .salary, salaryText: String = "", onFinish: @escaping () -> Void) {
        self.model = model
        self.onFinish = onFinish
        _step = State(initialValue: step)
        _salaryText = State(initialValue: salaryText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingStepper(step: step)
            content
                .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.bg)
        // 窗口标题栏透明、内容铺满 (见 `OnboardingWindowController`)，不让出标题栏的安全区。
        .ignoresSafeArea()
    }

    /// 按已填内容试算的提示，第 1、3 步用；每次重绘都重新试算，跟着输入走。
    private var preview: OnboardingPreview? { OnboardingPreview(model: model, input: input) }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .salary:
            OnboardingSalaryStep(salaryText: $salaryText, preview: preview, errorMessage: errorMessage, onSubmit: next)
        case .schedule:
            OnboardingScheduleStep(draft: $scheduleDraft, errorMessage: errorMessage)
        case .launch:
            OnboardingLaunchStep(launchAtLogin: $launchAtLogin, preview: preview, errorMessage: errorMessage)
        }
    }

    /// 设计稿 Footer：左右 24、下 22，按钮间隔 8；「上一步」高 37，主按钮上下内边距 11 (高 41)，顶端对齐。
    private var footer: some View {
        HStack(alignment: .top, spacing: Spacing.s8) {
            if let previous = step.previous {
                Button { move(to: previous) } label: {
                    Label { Text("上一步") } icon: { PhosphorIcon(.OnboardingIcon.arrowLeft) }
                }
                .buttonStyle(.secondary)
            }
            Button(action: next) {
                Text(step.next == nil ? "开始搬砖" : "下一步").padding(.vertical, OnboardingLayout.primaryButtonPadding)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.primary(fullWidth: true))
        }
        .padding(.horizontal, OnboardingLayout.side)
        .padding(.bottom, OnboardingLayout.bottom)
    }

    private func next() {
        let error: CommandError? = switch step {
        case .salary: Validation.monthlySalary(parsedSalary ?? 0)
        case .schedule: Validation.schedule(scheduleDraft.schedule)
        case .launch: nil
        }
        if let error {
            errorMessage = error.message
        } else if let next = step.next {
            move(to: next)
        } else {
            finish()
        }
    }

    private func finish() {
        do {
            try model.send(.completeOnboarding(input))
        } catch {
            errorMessage = error.message
            return
        }
        LaunchAtLogin.set(enabled: launchAtLogin)
        onFinish()
    }

    private func move(to step: OnboardingStep) {
        errorMessage = nil
        self.step = step
    }

    private var parsedSalary: Decimal? { SalaryText.parse(salaryText) }

    private var input: OnboardingInput {
        OnboardingInput(monthlySalary: parsedSalary ?? 0, schedule: scheduleDraft.schedule, launchAtLogin: launchAtLogin)
    }
}

/// 引导的三步，原始值即第几步。
enum OnboardingStep: Int, CaseIterable {
    case salary = 1, schedule, launch

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

/// 设计稿 Stepper：左边三个 6pt 高的圆角点，当前步拉长到 22、已到过的步为 accent，右边「1 / 3」。
struct OnboardingStepper: View {
    let step: OnboardingStep

    private static let dotHeight: CGFloat = 6
    private static let dotWidth: CGFloat = 8
    private static let currentDotWidth: CGFloat = 22

    var body: some View {
        HStack {
            HStack(spacing: OnboardingLayout.dotGap) {
                ForEach(OnboardingStep.allCases, id: \.self) { dot in
                    Capsule()
                        .fill(dot.rawValue <= step.rawValue ? Palette.accent : Palette.line)
                        .frame(width: dot == step ? Self.currentDotWidth : Self.dotWidth, height: Self.dotHeight)
                }
            }
            Spacer()
            Text("\(step.rawValue) / \(OnboardingStep.allCases.count)")
                .font(AppFont.numSmall)
                .foregroundStyle(Palette.muted)
        }
        .padding(.top, OnboardingLayout.stepperTop)
        .padding(.horizontal, OnboardingLayout.side)
        .animation(.easeOut(duration: 0.2), value: step)
    }
}

/// 引导页的排版尺寸 (设计稿 P1 引导)，`Spacing` 里没有的值集中在这里。
enum OnboardingLayout {
    /// 左右内边距。
    static let side = Spacing.s24
    /// 步骤条上边距。
    static let stepperTop: CGFloat = 18
    /// 步骤点间隔。
    static let dotGap: CGFloat = 5
    /// 正文区上下内边距，与底部按钮区下边距相同。
    static let bottom: CGFloat = 22
    /// 主按钮上下内边距，按钮高 41 (比 `ThemeButtonStyle.height` 高 4)。
    static let primaryButtonPadding: CGFloat = 11
    /// 灰底分组 (午休、开机自启) 与预览框的圆角。
    static let groupRadius = Radius.r10
}
