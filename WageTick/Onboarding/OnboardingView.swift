import SwiftUI
import WageCore

/// 2 步引导：月薪 (含休息模式) → 作息 (含饭点) (PRD 4.1.1、F1；设计稿 P1 引导 · 1 月薪 · 760、P1 引导 · 2 作息 · 760)。
/// 开机自启不再询问，按 PRD 4.7.2 的默认值 (开) 保存并注册登录项，之后在设置里改。
/// 标题栏下是步骤条，中间是当前步，底部「上一步」与「下一步 / 开始搬砖」。
/// 每一步点"下一步"时用核心的 `Validation` 校验，失败停留当前步并展示提示。
struct OnboardingView: View {
    let model: AppModel
    let onFinish: () -> Void

    @State private var step: OnboardingStep
    @State private var salaryText: String
    @State private var restMode: RestModeChoice
    @State private var scheduleDraft = ScheduleDraft(.default)
    @State private var errorMessage: String?

    /// `step`、`salaryText`、`restMode` 只在离屏截图时指定，App 里从第 1 步、空月薪、双休开始。
    init(
        model: AppModel, step: OnboardingStep = .salary, salaryText: String = "", restMode: RestModeChoice = .twoDaysOff,
        onFinish: @escaping () -> Void
    ) {
        self.model = model
        self.onFinish = onFinish
        _step = State(initialValue: step)
        _salaryText = State(initialValue: salaryText)
        _restMode = State(initialValue: restMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingStepper(step: step)
            // 设计稿两屏都放得下；万一放不下 (如校验提示较长)，中间滚动，步骤条与底部按钮不动。
            ScrollBody { content }
            footer
        }
        .frame(width: WindowMetrics.size.width, height: WindowMetrics.size.height)
        .background(Palette.bg)
        // 窗口标题栏透明、内容铺满 (见 `OnboardingWindowController`)，不让出标题栏的安全区。
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .salary:
            OnboardingSalaryStep(salaryText: $salaryText, restMode: $restMode, errorMessage: errorMessage, onSubmit: next)
        case .schedule:
            OnboardingScheduleStep(draft: $scheduleDraft, rates: rates, errorMessage: errorMessage)
        }
    }

    /// 「按这个作息算」：把已填内容当作完成引导试算一遍 (不保存)，取快照里的工资换算，不自己算钱。
    /// 每次重绘都重新试算，跟着作息与第 1 步选的休息模式走；作息不合法 (试算被校验拦下) 时为 nil，整块不显示。
    private var rates: WageRates? {
        guard case .success(let snapshot) = model.dryRun(.completeOnboarding(input)) else { return nil }
        return snapshot.wageRates
    }

    /// 设计稿 Footer：左右 24、下 24，按钮间隔 8、高 44；「上一步」按内容宽，主按钮占满剩余宽度。
    private var footer: some View {
        HStack(spacing: Spacing.s8) {
            if let previous = step.previous {
                Button { move(to: previous) } label: {
                    Label { Text("上一步") } icon: { PhosphorIcon(.OnboardingIcon.arrowLeft) }
                        .frame(height: OnboardingLayout.buttonHeight)
                }
                .buttonStyle(.secondary)
            }
            Button(action: next) {
                Text(step.next == nil ? "开始搬砖" : "下一步").frame(height: OnboardingLayout.buttonHeight)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.primary(fullWidth: true))
        }
        .padding(.horizontal, OnboardingLayout.side)
        .padding(.bottom, OnboardingLayout.footerBottom)
    }

    private func next() {
        let error: CommandError? = switch step {
        case .salary: Validation.monthlySalary(parsedSalary ?? 0)
        case .schedule: Validation.schedule(scheduleDraft.schedule)
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
        let input = input
        do {
            try model.send(.completeOnboarding(input))
        } catch {
            errorMessage = error.message
            return
        }
        LaunchAtLogin.set(enabled: input.launchAtLogin)
        onFinish()
    }

    private func move(to step: OnboardingStep) {
        errorMessage = nil
        self.step = step
    }

    private var parsedSalary: Decimal? { SalaryText.parse(salaryText) }

    /// 开机自启不传，取核心的默认值 (PRD 4.7.2：开)。
    private var input: OnboardingInput {
        OnboardingInput(monthlySalary: parsedSalary ?? 0, schedule: scheduleDraft.schedule, restMode: restMode)
    }
}

/// 引导的两步，原始值即第几步。
enum OnboardingStep: Int, CaseIterable {
    case salary = 1, schedule

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

/// 设计稿 Stepper：标题栏 (红绿灯) 下面一行，上 14、左右 24。
/// 左边每步一个 6pt 高的圆角点，当前步拉长到 22、已到过的步为 accent；右边「1 / 2」。
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
        .padding(.top, WindowChrome.Titlebar.standard.height + Spacing.s14)
        .padding(.horizontal, OnboardingLayout.side)
        .animation(.easeOut(duration: 0.2), value: step)
    }
}

/// 引导页的排版尺寸 (设计稿 P1 引导 · 760)，`Spacing` 里没有的值集中在这里。
enum OnboardingLayout {
    /// 左右内边距。
    static let side = Spacing.s24
    /// 底部按钮区下边距。
    static let footerBottom = Spacing.s24
    /// 底部按钮高 (比 `ThemeButtonStyle.height` 高 7)。
    static let buttonHeight: CGFloat = 44
    /// 步骤点间隔。
    static let dotGap: CGFloat = 5
    /// 步骤条下面第一块 (第 1 步小牛、第 2 步标题) 的上边距。
    static let firstTop: CGFloat = 44
    /// 第 1 步标题离小牛。
    static let introAfterMascot: CGFloat = 28
    /// 正文区上下内边距。
    static let bodyTop: CGFloat = 36
    static let bodyBottom = Spacing.s22
    /// 时间输入框里的向下箭头。
    static let caretSize: CGFloat = 14
    /// 工资换算卡片里两项之间的竖线高。
    static let statDividerHeight: CGFloat = 34
}
