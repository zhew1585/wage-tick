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

/// 扣钱表单 (PRD F5，设计稿「弹窗-今天扣钱了」)：红色头图里是大号金额输入 (白色大字、黄色光标) 与今日上限的变化，
/// 大哭的小牛；下面按金额 / 按日薪百分比、快捷金额 (只在按金额时)、为啥被扣的三个方块、备注；底部「算了」与「记下这笔 −¥50」。
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
    /// 标题栏右侧的日期，如「11月5日 周四」；nil 时不显示。
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

    /// 快捷金额 (设计稿只有这四个)。
    private static let quickAmounts: [Int] = [20, 50, 100, 200]
    /// 原因方块的图标。
    private static let reasonIcons: [DeductionReason: Phosphor] = [.late: .alarm, .leftEarly: .door, .other: .dotsThree]

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
        // 每次刷新只试算一次。
        let draft = draftEntry
        let amountText = draft == nil ? nil : entry?.amountText(amount)
        FormSheet { collapse in
            BoldHero(
                theme: .red,
                back: HeroBack(label: "返回", action: dismiss),
                titlebarTrailing: subtitle,
                titlebarTrailingInset: PanelMetrics.pinInset,
                kicker: title,
                caption: caption(draft),
                captionIcon: .wallet,
                cow: .crying,
                bubble: HeroBubbleContent(value: "我的钱包…", numeric: false),
                collapse: collapse,
                compactValue: amountText ?? "−¥"
            ) {
                valueInput
            }
        } content: {
            BoldSegmented(selection: $method, options: [(.fixed, "按金额"), (.percent, "按日薪百分比")])
            if method == .fixed {
                quickAmounts
            }
            messages(draft)
            reasonPicker
            noteField
        } actions: {
            FormCancelButton(action: dismiss)
            Button(action: save) {
                Label { Text(saveTitle(amountText)) } icon: { PhosphorIcon(.check) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.pill(.ink))
        }
        .onAppear { focus = .value }
        .onChange(of: method) { errorMessage = nil }
        .onChange(of: valueText) { errorMessage = nil }
    }

    // MARK: 头图

    /// 头图里的大号金额输入 (规格同引导第 1 步，见 `HeroNumberInput`)：墨色「−¥」(按百分比时只有「−」、后面接「%」) + 白色 Archivo Black 数字。
    /// 字号固定不缩放；按金额最多 5 位数字、按百分比最多 3 位，都可带两位小数。
    private var valueInput: some View {
        let shown = valueText.isEmpty ? "0" : valueText
        let font = AppFont.heavy(HeroNumberInput.size)
        return HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
            Text(method == .fixed ? "−¥" : "−").font(AppFont.heavy(HeroNumberInput.affixSize)).foregroundStyle(Palette.ink)
            // 一段同字号文字撑出输入框宽度，让单位贴在数字后面；没填时它就是半透明的占位「0」
            // (系统的占位色是半透明黑，压在红底上发脏)。
            Text(shown)
                .font(font)
                .foregroundStyle(.white.opacity(valueText.isEmpty ? 0.45 : 0))
                .padding(.trailing, Spacing.s6)
                .overlay(alignment: .leading) {
                    TextField(method == .fixed ? "扣了多少" : "日薪的百分之几", text: $valueText, prompt: Text(""))
                        .textFieldStyle(.plain)
                        // 光标白色：面板每秒刷新时 SwiftUI 会按 tint 重设光标颜色，只改字段编辑器会被盖掉。
                        .tint(.white)
                        .font(font)
                        .foregroundStyle(.white)
                        .focused($focus, equals: .value)
                        .onSubmit(save)
                }
            if method == .percent {
                Text("%").font(AppFont.heavy(HeroNumberInput.affixSize)).foregroundStyle(Palette.ink)
            }
        }
        .heroNumberLimit($valueText, maxDigits: method == .fixed ? 5 : 3, maxDecimals: 2)
        .frame(height: 76, alignment: .bottomLeading)
        .padding(.top, HeroNumberInput.caretClearance)
        .contentShape(Rectangle())
        .onTapGesture { focus = .value }
        .cursor(.iBeam)
    }

    /// 头图说明「今日上限 ¥1000 → ¥950」：起点取当前快照，终点取草稿试算后的快照；还没填好时只显示起点。
    /// 填好时标题取核心的 `previewTitle` (按日薪百分比时前面加「扣 ¥100 ·」)。跨过零点没有入口时不显示。
    private func caption(_ draft: DeductionEntry?) -> String? {
        guard let entry else { return nil }
        guard let draft else { return "\(entry.capTitle) \(entry.capText)" }
        return "\(entry.previewTitle(amount)) \(entry.capText) → \(draft.capText)"
    }

    // MARK: 内容

    /// 快捷金额：一排四个，点了直接填进金额；与金额相同的那个选中。
    private var quickAmounts: some View {
        HStack(spacing: Spacing.s8) {
            ForEach(Self.quickAmounts, id: \.self) { value in
                Button("¥\(value)") {
                    valueText = "\(value)"
                    focus = .value
                }
                .buttonStyle(BoldChoiceStyle(selected: valueText == "\(value)", font: AppFont.heavy(14)))
            }
        }
    }

    /// 超过日薪的提醒 (PRD 4.3.5 #6) 与保存失败的校验提示。
    @ViewBuilder
    private func messages(_ draft: DeductionEntry?) -> some View {
        if let warning = draft?.warning {
            Text(warning).font(AppFont.caption).foregroundStyle(Palette.accent)
        }
        if let errorMessage {
            Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
        }
    }

    /// 原因方块可不选：再点一次已选中的即取消。
    private var reasonPicker: some View {
        FormGroup("为啥被扣 (可不选)") {
            HStack(spacing: Spacing.s8) {
                ForEach(DeductionReason.allCases, id: \.self) { option in
                    Button { reason = reason == option ? nil : option } label: {
                        TileLabel(title: option.label, icon: Self.reasonIcons[option] ?? .dotsThree)
                    }
                    .buttonStyle(BoldTileStyle(selected: reason == option))
                    .accessibilityAddTraits(reason == option ? .isSelected : [])
                }
            }
        }
    }

    /// 备注框：surface 底、高 48、圆角 16，文字 14，右边字数 (超出上限的部分直接截掉)；聚焦时墨色描边。
    private var noteField: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r16)
        return FormGroup("备注") {
            HStack(spacing: Spacing.s8) {
                TextField("备注", text: $note, prompt: Text("可不填").foregroundStyle(Palette.muted))
                    .textFieldStyle(.plain)
                    .font(AppFont.fieldText)
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .note)
                Text("\(note.count)/\(Validation.deductionNoteLimit)")
                    .font(AppFont.numSmall)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, Spacing.s16)
            .frame(height: Self.noteHeight)
            .background(Palette.surface, in: shape)
            .overlay(shape.strokeBorder(focus == .note ? Palette.ink : .clear, lineWidth: 1.5))
            .contentShape(shape)
            // 点框里任意处都聚焦到备注。
            .onTapGesture { focus = .note }
            .cursor(.iBeam)
            .onChange(of: note) {
                if note.count > Validation.deductionNoteLimit {
                    note = String(note.prefix(Validation.deductionNoteLimit))
                }
            }
        }
    }

    private static let noteHeight: CGFloat = 48

    // MARK: 文案与命令

    private var title: String {
        switch (request, target) {
        case (.edit, _): "改一笔扣钱"
        case (.add, .today): "今天又被扣了"
        case (.add, .day): "补记扣钱"
        }
    }

    /// 保存按钮：新记「记下这笔 −¥50」，修改「保存 −¥50」；还没填好时不带金额。
    private func saveTitle(_ amountText: String?) -> String {
        let verb = if case .edit = request { "保存" } else { "记下这笔" }
        return amountText.map { "\(verb) \($0)" } ?? verb
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
