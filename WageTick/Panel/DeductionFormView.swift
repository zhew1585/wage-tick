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
enum DeductionFormRequest: Identifiable, Equatable {
    case add
    case edit(DeductionItem)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let item): "edit-\(item.id)"
        }
    }
}

/// 扣钱表单 (PRD F5，设计稿 F5 · 760)：按金额 / 按日薪百分比、大号金额输入、原因标签、备注，
/// 实时预览「今日上限 ¥x → ¥y」(按日薪百分比时前面加「扣 ¥z ·」)。
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
    /// 表头右侧的日期，如「11月5日 周四」；nil 时不显示。
    let subtitle: String?

    @State private var method: Method
    @State private var valueText: String
    @State private var reason: DeductionReason?
    @State private var note: String
    @State private var errorMessage: String?
    @FocusState private var focus: Focus?

    private enum Method: Hashable {
        case fixed, percent
    }

    private enum Focus: Hashable {
        case value, note
    }

    init(
        request: DeductionFormRequest, entry: DeductionEntry?, actions: PanelActions, target: FormTarget = .today,
        subtitle: String? = nil, dismiss: @escaping () -> Void
    ) {
        self.request = request
        self.entry = entry
        self.actions = actions
        self.target = target
        self.subtitle = subtitle
        self.dismiss = dismiss
        let input: DeductionInput? = if case .edit(let item) = request { item.input } else { nil }
        _method = State(initialValue: input.map { if case .percentOfDailyWage = $0.amount { .percent } else { .fixed } } ?? .fixed)
        _valueText = State(initialValue: input.map { NSDecimalNumber(decimal: $0.amount.value).stringValue } ?? "")
        _reason = State(initialValue: input?.reason)
        _note = State(initialValue: input?.note ?? "")
    }

    var body: some View {
        FormSheet(title: title, subtitle: subtitle, back: dismiss) {
            ThemeSegmented(selection: $method, options: [(.fixed, "按金额"), (.percent, "按日薪百分比")], size: .large)
            VStack(alignment: .leading, spacing: Spacing.s6) {
                valueInput
                previewLine
                messages
            }
            reasonPicker
            noteField
        } actions: {
            Button("算了", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.secondary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
            Button(action: save) { Label { Text("继续搬砖") } icon: { PhosphorIcon(.check) } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.primary(fullWidth: true, height: PanelMetrics.actionButtonHeight))
        }
        .onAppear { focus = .value }
        .onChange(of: method) { errorMessage = nil }
        .onChange(of: valueText) { errorMessage = nil }
    }

    /// 大号金额输入 (白底、圆角 12)：左边 loss 色的负号 36/600，数字 48/700，右边单位 (元 / %) 18；获得焦点时描边换成 loss。
    private var valueInput: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r12)
        return HStack(spacing: Spacing.s6) {
            Text("−").font(AppFont.num(36, .semibold)).foregroundStyle(Palette.loss)
            TextField(method == .fixed ? "扣了多少" : "日薪的百分之几", text: $valueText, prompt: Text("0").foregroundStyle(Palette.line))
                .textFieldStyle(.plain)
                .font(AppFont.num(48, .bold))
                .foregroundStyle(Palette.ink)
                .focused($focus, equals: .value)
                .onSubmit(save)
            Text(method == .fixed ? "元" : "%").font(AppFont.ui(18)).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.vertical, Spacing.s18)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(focus == .value ? Palette.loss : Palette.line, lineWidth: 1.5))
    }

    /// 「今日上限 ¥1000 → ¥950」(13 号)：起点取当前快照，终点取草稿试算后的快照；还没填好时只显示起点。
    /// 填好时标题取核心的 `previewTitle` (按日薪百分比时前面加「扣 ¥100 ·」)。
    @ViewBuilder
    private var previewLine: some View {
        if let entry {
            let draft = draftEntry
            HStack(spacing: Spacing.s6) {
                Text(draft == nil ? entry.capTitle : entry.previewTitle(amount))
                    .font(AppFont.body)
                Text(entry.capText).font(AppFont.num(13))
                if let draft {
                    PhosphorIcon(.arrowRight, size: 12)
                    Text(draft.capText).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.loss)
                }
            }
            .foregroundStyle(Palette.muted)
        }
    }

    /// 超过日薪的提醒 (PRD 4.3.5 #6) 与保存失败的校验提示。
    @ViewBuilder
    private var messages: some View {
        if let warning = draftEntry?.warning {
            Text(warning).font(AppFont.caption).foregroundStyle(Palette.accent)
        }
        if let errorMessage {
            Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
        }
    }

    /// 原因标签可不选：再点一次已选中的标签即取消。
    private var reasonPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            FormLabel("为啥被扣 (可不选)")
            HStack(spacing: Spacing.s6) {
                ForEach(DeductionReason.allCases, id: \.self) { option in
                    ReasonPill(title: option.label, selected: reason == option) {
                        reason = reason == option ? nil : option
                    }
                }
            }
        }
    }

    /// 备注框：白底、高 104、圆角 8，文字 14，右下角字数 (超出上限的部分直接截掉)。
    private var noteField: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return VStack(alignment: .leading, spacing: Spacing.s8) {
            FormLabel("备注")
            VStack(alignment: .leading, spacing: 0) {
                TextField("备注", text: $note, prompt: Text("可不填").foregroundStyle(Palette.muted), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppFont.fieldText)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...3)
                    .focused($focus, equals: .note)
                Spacer(minLength: 0)
                Text("\(note.count)/\(Validation.deductionNoteLimit)")
                    .font(AppFont.numSmall)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, Spacing.s14)
            .padding(.vertical, Spacing.s12)
            .frame(height: Self.noteHeight)
            .contentShape(shape)
            // 点框里任意处都聚焦到备注。
            .onTapGesture { focus = .note }
            .cursor(.iBeam)
            .background(Palette.card, in: shape)
            .overlay(shape.strokeBorder(focus == .note ? Palette.accent : Palette.line, lineWidth: 1))
            .onChange(of: note) {
                if note.count > Validation.deductionNoteLimit {
                    note = String(note.prefix(Validation.deductionNoteLimit))
                }
            }
        }
    }

    /// 备注框高度 (设计稿 Note Box)。
    private static let noteHeight: CGFloat = 104

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
        return switch request {
        case .add: target.command(today: .addDeduction(input), .addDeduction(input))
        case .edit(let item): target.command(today: .editDeduction(id: item.id, input), .editDeduction(id: item.id, input))
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

/// 原因标签：圆角 18 的胶囊，内边距 8 / 16，文字 13/500；选中墨色底浅色字，未选中透明底 line 描边。
/// 悬停、按下：选中的墨色底变浅 / 变深，未选中的叠一层底；手型光标。
private struct ReasonPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r18)
        return Button(action: action) {
            Text(title)
                .font(AppFont.bodyMedium)
                .foregroundStyle(selected ? Palette.bg : Palette.ink)
                .padding(.horizontal, Spacing.s16)
                .padding(.vertical, Spacing.s8)
        }
        .buttonStyle(InteractiveButtonStyle { label, state in
            label
                .background(fill(state), in: shape)
                .overlay(shape.strokeBorder(selected ? fill(state) : Palette.line, lineWidth: 1))
                .contentShape(shape)
        })
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func fill(_ state: InteractionState) -> Color {
        guard selected else { return state.overlay }
        if state.isPressed { return Palette.inkPressed }
        return state.isHovered ? Palette.inkHover : Palette.ink
    }
}
