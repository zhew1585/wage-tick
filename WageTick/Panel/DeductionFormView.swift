import SwiftUI
import WageCore

/// 面板发命令的两个口子，由窗口控制器接到 `AppModel` 上。
struct PanelActions {
    /// 试算：执行命令但不保存，返回执行后的快照。
    let dryRun: (Command) -> Result<Snapshot, CommandError>
    /// 执行命令并保存，校验失败时抛出。
    let send: (Command) throws(CommandError) -> Void
}

/// 打开扣钱表单的请求：新记一笔，或编辑已有的一笔。
enum DeductionFormRequest: Identifiable {
    case add
    case edit(DeductionItem)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let item): "edit-\(item.id)"
        }
    }
}

/// 扣钱表单 (PRD F5)：按金额 / 按日薪百分比、原因标签、备注，实时预览「今日上限 ¥x → ¥y」。
/// 预览与校验都来自核心：草稿交给 `dryRun` 试算，拿试算后快照里的扣钱入口与当前的对比。
/// 今日概览面板记今天的，历史单日详情补记那一天的 (#15)。
struct DeductionFormView: View {
    let request: DeductionFormRequest
    /// 当前快照里的扣钱入口，预览的起点；跨过零点变成休息日时为 nil。
    let entry: DeductionEntry?
    let actions: PanelActions
    let dismiss: () -> Void
    /// 作用的日子：今天或历史里的某一天。
    let target: FormTarget

    @State private var method: Method
    @State private var valueText: String
    @State private var reason: DeductionReason?
    @State private var note: String
    @State private var errorMessage: String?

    private enum Method: Hashable {
        case fixed, percent
    }

    init(
        request: DeductionFormRequest, entry: DeductionEntry?, actions: PanelActions, target: FormTarget = .today,
        dismiss: @escaping () -> Void
    ) {
        self.request = request
        self.entry = entry
        self.actions = actions
        self.target = target
        self.dismiss = dismiss
        let input: DeductionInput? = if case .edit(let item) = request { item.input } else { nil }
        _method = State(initialValue: input.map { if case .percentOfDailyWage = $0.amount { .percent } else { .fixed } } ?? .fixed)
        _valueText = State(initialValue: input.map { NSDecimalNumber(decimal: $0.amount.value).stringValue } ?? "")
        _reason = State(initialValue: input?.reason)
        _note = State(initialValue: input?.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title3.bold())
            Picker("记账方式", selection: $method) {
                Text("按金额").tag(Method.fixed)
                Text("按日薪百分比").tag(Method.percent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                TextField(method == .fixed ? "扣了多少" : "日薪的百分之几", text: $valueText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Text(method == .fixed ? "元" : "%").foregroundStyle(.secondary)
            }
            reasonPicker
            noteField
            previewSection
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            HStack {
                Button("取消", action: dismiss).keyboardShortcut(.cancelAction)
                Spacer()
                Button("继续搬砖", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onChange(of: method) { errorMessage = nil }
        .onChange(of: valueText) { errorMessage = nil }
    }

    /// 原因标签可不选：再点一次已选中的标签即取消。
    private var reasonPicker: some View {
        HStack {
            Text("原因").foregroundStyle(.secondary)
            ForEach(DeductionReason.allCases, id: \.self) { option in
                Toggle(option.label, isOn: Binding(
                    get: { reason == option },
                    set: { reason = $0 ? option : nil }
                ))
                .toggleStyle(.button)
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .trailing, spacing: 2) {
            TextField("备注 (可不填)", text: $note)
                .textFieldStyle(.roundedBorder)
                .onChange(of: note) {
                    if note.count > Validation.deductionNoteLimit {
                        note = String(note.prefix(Validation.deductionNoteLimit))
                    }
                }
            Text("\(note.count)/\(Validation.deductionNoteLimit)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        let draft = draftEntry
        if let entry {
            Text(entry.previewLine(to: draft))
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
        if let warning = draft?.warning {
            Text(warning).font(.callout).foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch (request, target) {
        case (.edit, _): "改一笔扣钱"
        case (.add, .today): "今天扣钱了"
        case (.add, .day): "补记扣钱"
        }
    }

    /// 草稿试算后的扣钱入口；还没填好 (校验不过) 时为 nil，预览只显示起点。
    private var draftEntry: DeductionEntry? {
        guard case .success(let snap) = actions.dryRun(command) else { return nil }
        return target.deductionEntry(in: snap)
    }

    private var command: Command {
        let input = DeductionInput(amount: amount, reason: reason, note: note)
        return switch (request, target) {
        case (.add, .today): .addDeduction(input)
        case (.edit(let item), .today): .editDeduction(id: item.id, input)
        case (.add, .day(let date)): .editDay(date, .addDeduction(input))
        case (.edit(let item), .day(let date)): .editDay(date, .editDeduction(id: item.id, input))
        }
    }

    /// 只认纯数字写法，其他写法视为 0；正数等规则交给核心校验。
    private var amount: DeductionAmount {
        let text = valueText.trimmingCharacters(in: .whitespaces)
        let value = text.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) == nil
            ? 0
            : Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        return method == .fixed ? .fixed(value) : .percentOfDailyWage(value)
    }

    private func save() {
        do {
            try actions.send(command)
            dismiss()
        } catch {
            errorMessage = error.message
        }
    }
}
