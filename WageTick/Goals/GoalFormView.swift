import SwiftUI
import WageCore

/// 新建目标，或编辑排队中、累计中目标的名称和金额 (PRD 4.5.2)，从目标管理弹出。
/// 编辑时初始值取自快照攒钱队列里的那一行 (`QueueGoalRow`)；校验交给核心，失败时展示 `CommandError.message`。
/// 改小金额导致已达标时核心会立即完成并激活下一个，这里不做判断。
struct GoalFormView: View {
    enum Mode: Identifiable {
        case create
        case edit(QueueGoalRow)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let row): "edit-\(row.id)"
            }
        }
    }

    let mode: Mode
    /// 保存：发 `.createGoal` 或 `.editGoal`，校验失败时抛出。
    let save: (Command) throws(CommandError) -> Void
    let dismiss: () -> Void

    @State private var name: String
    @State private var amountText: String
    @State private var errorMessage: String?

    init(mode: Mode, save: @escaping (Command) throws(CommandError) -> Void, dismiss: @escaping () -> Void) {
        self.mode = mode
        self.save = save
        self.dismiss = dismiss
        let row: QueueGoalRow? = if case .edit(let row) = mode { row } else { nil }
        _name = State(initialValue: row?.name ?? "")
        _amountText = State(initialValue: row?.amountInput ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s14) {
            Text(title).font(AppFont.sheetTitle).foregroundStyle(Palette.ink)
            Field("名称", text: $name, prompt: "如 Switch 2", value: .text)
            Field("金额", text: $amountText, suffix: "元")
                .onSubmit(submit)
            if let errorMessage {
                Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            HStack(spacing: Spacing.s8) {
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.secondary(fullWidth: true))
                Button(action: submit) { Label(isEditing ? "保存" : "新建", systemImage: isEditing ? "checkmark" : "plus") }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primary(fullWidth: true))
            }
        }
        .padding(Spacing.screen)
        .frame(width: 300)
        .background(Palette.bg)
        .onChange(of: name) { errorMessage = nil }
        .onChange(of: amountText) { errorMessage = nil }
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var title: String { isEditing ? "编辑目标" : "新目标" }

    private func submit() {
        let amount = AmountText.parse(amountText) ?? 0
        let command: Command = switch mode {
        case .create: .createGoal(name: name, amount: amount)
        case .edit(let row): .editGoal(id: row.id, name: name, amount: amount)
        }
        do {
            try save(command)
            dismiss()
        } catch {
            errorMessage = error.message
        }
    }
}
