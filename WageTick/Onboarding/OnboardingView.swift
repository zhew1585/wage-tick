import SwiftUI
import WageCore

/// 2 步引导：工资 (含休息模式) → 作息 (含饭点) (PRD 4.1.1、F1；大胆版设计稿「引导-1工资」「引导-2作息」)。
/// 开机自启不再询问，按 PRD 4.7.2 的默认值 (开) 保存并注册登录项，之后在设置里改。
/// 每步上面是橙色头图 (标题栏那行的胶囊写「1 / 2」「2 / 2」)，下面是这一步的选项，底部固定「上一步」与「下一步 / 开工」。
/// 每一步点"下一步"时用核心的 `Validation` 校验，失败停留当前步并弹窗提示。
struct OnboardingView: View {
    let model: AppModel
    let onFinish: () -> Void

    @State private var step: OnboardingStep
    @State private var salaryText: String
    @State private var payBasis: PayBasis
    @State private var restMode: RestModeChoice
    @State private var scheduleDraft = ScheduleDraft(.default)
    /// 校验失败时弹窗里的一句话；nil 时不弹。
    @State private var alertMessage: String?

    /// `step`、`salaryText`、`payBasis`、`restMode`、`alertMessage` 只在离屏截图时指定，App 里从第 1 步、空工资、按月、双休开始。
    init(
        model: AppModel, step: OnboardingStep = .salary, salaryText: String = "", payBasis: PayBasis = .monthly,
        restMode: RestModeChoice = .twoDaysOff, alertMessage: String? = nil, onFinish: @escaping () -> Void
    ) {
        self.model = model
        self.onFinish = onFinish
        _step = State(initialValue: step)
        _salaryText = State(initialValue: salaryText)
        _payBasis = State(initialValue: payBasis)
        _restMode = State(initialValue: restMode)
        _alertMessage = State(initialValue: alertMessage)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 两步都放得下；万一放不下 (如校验提示较长)，头图收起、正文滚动，底部按钮不动。
            HeroScroll { collapse in
                hero(collapse)
            } content: {
                content
            }
            .overlay(alignment: .topLeading) {
                HeroStepChip(text: "\(step.rawValue) / \(OnboardingStep.allCases.count)", theme: .orange)
            }
            footer
        }
        .frame(width: WindowMetrics.size.width, height: WindowMetrics.size.height)
        .background(Palette.bg)
        // 窗口标题栏透明、内容铺满 (见 `OnboardingWindowController`)，不让出标题栏的安全区。
        .ignoresSafeArea()
        // 校验失败的提醒用大胆版弹窗，小牛握拳提醒。
        .boldAlert($alertMessage, pose: .excited)
    }

    @ViewBuilder
    private func hero(_ collapse: CGFloat) -> some View {
        switch step {
        case .salary:
            OnboardingSalaryHero(salaryText: $salaryText, payBasis: payBasis, collapse: collapse, onSubmit: next)
        case .schedule:
            OnboardingScheduleHero(rates: rates, collapse: collapse)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .salary:
            OnboardingSalaryStep(payBasis: $payBasis, restMode: $restMode)
        case .schedule:
            OnboardingScheduleStep(draft: $scheduleDraft, rates: rates)
        }
    }

    /// 标准工时与汇总条：把已填内容当作完成引导试算一遍 (不保存)，取快照里的工资换算，不自己算钱。
    /// 每次重绘都重新试算，跟着作息与第 1 步选的休息模式走；作息不合法 (试算被校验拦下) 时为 nil。
    private var rates: WageRates? {
        guard case .success(let snapshot) = model.dryRun(.completeOnboarding(input)) else { return nil }
        return snapshot.wageRates
    }

    /// 底部按钮 (胶囊)：第 1 步只有墨色「下一步」；第 2 步左边描边「上一步」(108 宽)，右边墨色「开工」。
    private var footer: some View {
        HStack(spacing: Spacing.s10) {
            if let previous = step.previous {
                Button("上一步") { move(to: previous) }
                    .buttonStyle(.pill(.outline))
                    .frame(width: 108)
            }
            Button(step.next == nil ? "开工" : "下一步", action: next)
            // 弹窗出来时回车留给弹窗的「知道了」。
            .keyboardShortcut(alertMessage == nil ? .defaultAction : nil)
            .buttonStyle(.pill(.ink))
        }
        .padding(EdgeInsets(top: Spacing.s12, leading: Spacing.screen, bottom: Spacing.s20, trailing: Spacing.screen))
    }

    private func next() {
        let error: CommandError? = switch step {
        case .salary: Validation.salary(parsedSalary ?? 0, basis: payBasis)
        case .schedule: Validation.schedule(scheduleDraft.schedule)
        }
        if let error {
            alertMessage = Self.alertText(error, basis: payBasis)
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
            alertMessage = error.message
            return
        }
        LaunchAtLogin.set(enabled: input.launchAtLogin)
        onFinish()
    }

    private func move(to step: OnboardingStep) {
        self.step = step
    }

    /// 弹窗文案：没填工资时换成口语的「一个月 (一天) 赚多少要告诉我哦」，其余照核心的提示。
    private static func alertText(_ error: CommandError, basis: PayBasis) -> String {
        switch error {
        case .salaryNotPositive, .dailyWageNotPositive:
            basis == .daily ? "一天赚多少要告诉我哦" : "一个月赚多少要告诉我哦"
        default:
            error.message
        }
    }

    private var parsedSalary: Decimal? { SalaryText.parse(salaryText) }

    /// 开机自启不传，取核心的默认值 (PRD 4.7.2：开)。
    private var input: OnboardingInput {
        OnboardingInput(salary: parsedSalary ?? 0, payBasis: payBasis, schedule: scheduleDraft.schedule, restMode: restMode)
    }
}

/// 引导的两步，原始值即第几步。
enum OnboardingStep: Int, CaseIterable {
    case salary = 1, schedule

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}
