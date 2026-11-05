import SwiftUI
import WageCore

/// 请假表单 (PRD F6，设计稿 F6 · 760)，从今日概览面板 (今天) 或历史单日详情 (那一天，#15) 打开：
/// 时段 (每段下方是请掉的工时)、扣日薪的百分比 (右侧「= ¥500」)，下方汇总当日计划、请假扣薪、收入项 (今天为今日上限，历史为结算或预计结算)。
/// 汇总与校验提示都来自核心：每次改动都把待保存的命令交给 `PanelActions.dryRun` 试算。
struct LeaveFormView: View {
    /// 新请一条 (与已有的另一半天假合并) 还是修改已有的那条 (整条替换)。
    enum Mode: Equatable {
        case request
        case edit(Leave)
    }

    let mode: Mode
    let actions: PanelActions
    /// 打开时这天的请假表单 (今天取快照的 `leaveForm`)，用来给时段选项配工时；nil 时工时取自试算结果，比例填错时不显示。
    let initialForm: LeaveForm?
    /// 关闭表单：保存、撤销成功或取消后调用。
    let dismiss: () -> Void
    /// 作用的日子：今天或历史里的某一天。
    let target: FormTarget
    /// 表头右侧的日期，如「11月5日 周四」；nil 时不显示。
    let subtitle: String?

    @State private var period: LeavePeriod
    @State private var percentText: String
    @State private var errorMessage: String?
    @FocusState private var percentFocused: Bool

    /// 汇总下方的说明 (设计稿 F6)。
    private static let hint = "病假打折、年假不扣，可按需调整。请假日仍算应出勤日。"

    init(
        mode: Mode, actions: PanelActions, initialForm: LeaveForm? = nil, target: FormTarget = .today,
        subtitle: String? = nil, dismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.actions = actions
        self.initialForm = initialForm
        self.target = target
        self.subtitle = subtitle
        self.dismiss = dismiss
        let initial = switch mode {
        case .request: Leave(period: .fullDay, deductionPercent: LeavePeriod.fullDay.defaultDeductionPercent)
        case .edit(let leave): leave
        }
        _period = State(initialValue: initial.period)
        _percentText = State(initialValue: Self.text(initial.deductionPercent))
    }

    var body: some View {
        FormSheet(title: mode == .request ? "请假" : "修改请假", subtitle: subtitle, back: dismiss) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                FormLabel("时段")
                ThemeSegmented(
                    options: LeavePeriod.allCases.map { .init(id: $0, title: $0.label, subtitle: periodHours[$0]) },
                    selection: period,
                    size: .large
                ) { period = $0 }
                // 切换时段时带出默认比例【D4】，牛马可再修改。
                .onChange(of: period) { _, newValue in
                    percentText = Self.text(newValue.defaultDeductionPercent)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.s8) {
                FormLabel("扣日薪的")
                percentInput
            }
            summary
        } actions: {
            buttons
        }
        .onAppear { percentFocused = true }
        .onChange(of: percentText) { errorMessage = nil }
    }

    /// 比例输入 (白底、圆角 12、内边距 16)：数字 36/700，紧跟着「%」18，右侧试算出的「= ¥500」16/600 loss；获得焦点时描边换成墨色。
    private var percentInput: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r12)
        let font = AppFont.num(36, .bold)
        return HStack(spacing: Spacing.s6) {
            // 用一段隐藏的同字号文字撑出输入框宽度，让「%」贴在数字后面。
            Text(percentText.isEmpty ? "0" : percentText)
                .font(font)
                .hidden()
                .padding(.trailing, Spacing.s4)
                .overlay(alignment: .leading) {
                    TextField("扣日薪的百分比", text: $percentText, prompt: Text("0").foregroundStyle(Palette.line))
                        .textFieldStyle(.plain)
                        .font(font)
                        .foregroundStyle(Palette.ink)
                        .focused($percentFocused)
                        .onSubmit(save)
                }
            Text("%").font(AppFont.ui(18)).foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
            if let deduction = previewForm?.deductionText {
                Text("= \(deduction)").font(AppFont.num(16, .semibold)).foregroundStyle(Palette.loss)
            }
        }
        .padding(Spacing.s16)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(percentFocused ? Palette.ink : Palette.line, lineWidth: 1.5))
        .contentShape(shape)
        // 点框里任意处都聚焦到输入框，整框显示 I 型光标。
        .onTapGesture { percentFocused = true }
        .cursor(.iBeam)
    }

    /// 汇总框 (surface 底、圆角 12、内边距 16、行距 12)：每行标题 13 + 数值 (等宽 13/600，扣薪 loss 色)，
    /// 下方一条分隔线与说明 12；比例填错时这里换成核心的校验提示。
    private var summary: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            switch previewResult {
            case .success(let form):
                ForEach(form?.summary ?? [], id: \.title) { item in
                    HStack {
                        Text(item.title).font(AppFont.body).foregroundStyle(Palette.muted)
                        Spacer()
                        Text(item.value)
                            .font(AppFont.num(13, .semibold))
                            .foregroundStyle(item.value.hasPrefix("−") ? Palette.loss : Palette.ink)
                    }
                }
            case .failure(let error):
                Text(error.message).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            if let errorMessage {
                Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            Text(Self.hint)
                .font(AppFont.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r12))
    }

    @ViewBuilder
    private var buttons: some View {
        if case .edit = mode {
            Button("撤销请假", role: .destructive) { send(cancelCommand) }
                .buttonStyle(.secondary(fullWidth: false, height: PanelMetrics.actionButtonHeight))
        }
        Button("算了", action: dismiss)
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.secondary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
        Button(action: save) { Label { Text(mode == .request ? "就这么请" : "保存") } icon: { PhosphorIcon(.check) } }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.primary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
    }

    private func save() {
        switch pendingCommand {
        case .success(let command): send(command)
        case .failure(let error): errorMessage = error.message
        }
    }

    private func send(_ command: Command) {
        do {
            try actions.send(command)
            dismiss()
        } catch {
            errorMessage = error.message
        }
    }

    /// 待保存的命令；比例没填或不是数字时给出核心的校验提示 (PRD 4.3.5 #22)。
    private var pendingCommand: Result<Command, CommandError> {
        guard let percent = parsedPercent else {
            return .failure(Validation.leaveDeductionPercent(nil) ?? .leavePercentOutOfRange)
        }
        let leave = Leave(period: period, deductionPercent: percent)
        return .success(mode == .request
            ? target.command(today: .requestLeave(leave), .requestLeave(leave))
            : target.command(today: .editLeave(leave), .editLeave(leave)))
    }

    private var cancelCommand: Command {
        target.command(today: .cancelLeave, .cancelLeave)
    }

    /// 试算结果：命令被核心拒绝时为对应提示；那天没有请假表单时 (理论上不会) 为 nil。
    private var previewResult: Result<LeaveForm?, CommandError> {
        pendingCommand.flatMap { actions.dryRun($0) }.map(target.leaveForm(in:))
    }

    /// 试算成功时的表单；比例填错时为 nil。
    private var previewForm: LeaveForm? {
        if case .success(let form) = previewResult { form } else { nil }
    }

    /// 各时段下方的工时：优先取打开时的表单 (不随填写变化)，没有时取试算结果。
    private var periodHours: [LeavePeriod: String] {
        initialForm?.periodHours ?? previewForm?.periodHours ?? [:]
    }

    /// 只认纯数字写法 (可带小数)，其他写法视为未填；范围交给核心的 `Validation`。
    private var parsedPercent: Decimal? {
        let text = percentText.trimmingCharacters(in: .whitespaces)
        guard text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// 比例填进输入框的写法，如 `100`、`12.5`。
    private static func text(_ percent: Decimal) -> String {
        NSDecimalNumber(decimal: percent).stringValue
    }
}

extension LeaveFormView.Mode: Identifiable {
    /// 供 `.sheet(item:)` 区分新请与修改。
    var id: String {
        switch self {
        case .request: "request"
        case .edit: "edit"
        }
    }
}
