import SwiftUI
import WageCore

/// 请假表单 (PRD F6，设计稿「弹窗-请假」)，从今日概览面板 (今天) 或历史单日详情 (那一天，#15) 打开：
/// 黄色头图里是请掉的时长 (大数字「2 小时」) 与「时段 · 扣多少」，晒太阳的小牛；
/// 下面「请哪段」时间条 (拖两头的把手选时段，下面快捷的全天、前半天、后半天)、「扣多少」一行 (扣日薪的百分比可改，右边试算出的金额) 与说明；
/// 底部「算了」与「请假 −¥285.70」，修改时多一个「撤销请假」。
/// 金额与校验提示都来自核心：每次改动都把待保存的命令交给 `PanelActions.dryRun` 试算；时间条的吸附与时段文字问 `LeaveBar`。
struct LeaveFormView: View {
    /// 新请一条还是修改已有的那条；一天只有一条，两者都发 `setLeave` (整条替换)，只影响标题和按钮。
    enum Mode: Equatable {
        case request
        case edit(Leave)
    }

    let mode: Mode
    /// 打开时这天的请假表单，时间条取自它 (作息不随填写变化)。
    let form: LeaveForm
    let actions: PanelActions
    /// 关闭表单：保存、撤销成功或取消后调用。
    let dismiss: () -> Void
    /// 作用的日子：今天或历史里的某一天。
    let target: FormTarget
    /// 标题栏右侧的日期，如「11月5日 周四」；nil 时不显示。
    let subtitle: String?

    @State private var range: LeaveRange
    @State private var percentText: String
    @State private var errorMessage: String?
    @FocusState private var percentFocused: Bool

    /// 「扣多少」下方的说明 (设计稿「弹窗-请假」)。
    private static let hint = "按请掉的工时占比算，饭点不算。病假打折、年假不扣，可以改。请假日仍算应出勤日。"

    init(
        mode: Mode, form: LeaveForm, actions: PanelActions, target: FormTarget = .today,
        subtitle: String? = nil, dismiss: @escaping () -> Void
    ) {
        self.mode = mode
        self.form = form
        self.actions = actions
        self.target = target
        self.subtitle = subtitle
        self.dismiss = dismiss
        let initial = switch mode {
        case .request: Leave(range: form.bar.fullDay, deductionPercent: form.bar.defaultPercent(for: form.bar.fullDay))
        case .edit(let leave): leave
        }
        _range = State(initialValue: initial.range)
        _percentText = State(initialValue: Self.text(initial.deductionPercent))
    }

    var body: some View {
        // 每次刷新只试算一次。
        let preview = previewResult
        let deduction: String? = if case .success(let form) = preview { form?.deductionText } else { nil }
        let title = form.bar.title(of: range)
        let duration = Self.split(title.duration)
        FormSheet { collapse in
            BoldHero(
                theme: .sun,
                back: HeroBack(label: "返回", action: dismiss),
                titlebarTrailing: subtitle,
                kicker: mode == .request ? "请个假，歇一歇" : "修改请假",
                caption: caption(range: title.range, deduction: deduction),
                captionIcon: .clock,
                cow: .pose(.sunbathing),
                bubble: HeroBubbleContent(value: "终于能歇了", numeric: false),
                collapse: collapse,
                compactValue: duration.number
            ) {
                HeroAmount(text: duration.number, theme: .sun, unit: duration.unit, size: 110, maxWidth: 200)
            }
        } content: {
            FormGroup("请哪段") {
                LeaveBarView(bar: form.bar, range: $range)
                    // 时段变了就按工时占比重新带出比例【D4】，手改的比例保留到下次改时段。
                    .onChange(of: range) { _, newValue in
                        percentText = Self.text(form.bar.defaultPercent(for: newValue))
                    }
            }
            FormGroup("扣多少") {
                percentRow(deduction)
                messages(preview)
                Text(Self.hint)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            buttons(deduction)
        }
        .onAppear { percentFocused = true }
        .onChange(of: percentText) { errorMessage = nil }
        .onChange(of: range) { errorMessage = nil }
    }

    /// 「扣日薪的 28.57%」一行 (surface 底、圆角 14、高 48)：比例可改 (Archivo Black 20)，右边试算出的「−¥285.70」loss 色；
    /// 获得焦点时墨色描边。
    private func percentRow(_ deduction: String?) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r14)
        let font = AppFont.heavy(20)
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text("扣日薪的").font(AppFont.ui(13)).foregroundStyle(Palette.muted).padding(.trailing, Spacing.s6)
            // 用一段隐藏的同字号文字撑出输入框宽度，让「%」贴在数字后面。
            Text(percentText.isEmpty ? "0" : percentText)
                .font(font)
                .hidden()
                .padding(.trailing, Spacing.s2)
                .overlay(alignment: .leading) {
                    TextField("扣日薪的百分比", text: $percentText, prompt: Text("0").foregroundStyle(Palette.line))
                        .textFieldStyle(.plain)
                        .font(font)
                        .foregroundStyle(Palette.ink)
                        .focused($percentFocused)
                        .onSubmit(save)
                }
            Text("%").font(font).foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.s8)
            if let deduction {
                Text(deduction).font(AppFont.heavy(18)).foregroundStyle(Palette.loss)
            }
        }
        .padding(.horizontal, Spacing.s16)
        .frame(height: 48)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(percentFocused ? Palette.ink : .clear, lineWidth: 1.5))
        .contentShape(shape)
        // 点框里任意处都聚焦到输入框，整框显示 I 型光标。
        .onTapGesture { percentFocused = true }
        .cursor(.iBeam)
    }

    /// 比例填错时核心的校验提示，与保存失败的提示。
    @ViewBuilder
    private func messages(_ preview: Result<LeaveForm?, CommandError>) -> some View {
        if case .failure(let error) = preview {
            Text(error.message).font(AppFont.caption).foregroundStyle(Palette.loss)
        }
        if let errorMessage {
            Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
        }
    }

    /// 新请：「算了」+「请假 −¥285.70」；修改：「撤销请假」+「算了」+「保存」(三个放不下金额)。
    @ViewBuilder
    private func buttons(_ deduction: String?) -> some View {
        switch mode {
        case .request:
            FormCancelButton(action: dismiss)
            Button(action: save) {
                Label { Text(deduction.map { "请假 \($0)" } ?? "请假") } icon: { PhosphorIcon(.umbrella) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.pill(.ink))
        case .edit:
            Button("撤销请假") { send(cancelCommand) }
                .buttonStyle(.pill(.outline, fullWidth: false))
            Button("算了", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.pill(.outline, fullWidth: false))
            Button(action: save) { Label { Text("保存") } icon: { PhosphorIcon(.check) } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.pill(.ink))
        }
    }

    /// 头图说明「14:00 – 16:00 · 扣 ¥285.70」：金额去掉负号接在「扣」后面 (不断行)；比例填错时只有时段。
    private func caption(range: String, deduction: String?) -> String {
        guard let deduction else { return range }
        return "\(range) · 扣\u{00A0}\(deduction.replacingOccurrences(of: "−", with: ""))"
    }

    /// 时长「2 小时」拆成大数字「2」与单位「小时」；「1 小时 30 分」拆成「1」与「小时 30 分」。
    private static func split(_ duration: String) -> (number: String, unit: String?) {
        guard let space = duration.firstIndex(of: " ") else { return (duration, nil) }
        return (String(duration[..<space]), String(duration[duration.index(after: space)...]))
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
        let leave = Leave(range: range, deductionPercent: percent)
        return .success(target.command(today: .setLeave(leave), .setLeave(leave)))
    }

    private var cancelCommand: Command {
        target.command(today: .cancelLeave, .cancelLeave)
    }

    /// 试算结果：命令被核心拒绝时为对应提示；那天没有请假表单时 (理论上不会) 为 nil。
    private var previewResult: Result<LeaveForm?, CommandError> {
        pendingCommand.flatMap { actions.dryRun($0) }.map(target.leaveForm(in:))
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
