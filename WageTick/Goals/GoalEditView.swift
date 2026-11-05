import SwiftUI
import WageCore

/// 编辑排队中或累计中目标的名称和金额 (PRD 4.5.2)，从目标管理列表弹出。
/// 初始值取自快照的 `GoalRow`；校验交给核心，失败时展示 `CommandError.message`。
/// 改小金额导致已达标时核心会立即完成并激活下一个，这里不做判断。
struct GoalEditView: View {
    let row: GoalRow
    /// 保存：发 `.editGoal`，校验失败时抛出。
    let save: (String, Decimal) throws(CommandError) -> Void
    let dismiss: () -> Void

    @State private var name: String
    @State private var amountText: String
    @State private var errorMessage: String?

    init(row: GoalRow, save: @escaping (String, Decimal) throws(CommandError) -> Void, dismiss: @escaping () -> Void) {
        self.row = row
        self.save = save
        self.dismiss = dismiss
        _name = State(initialValue: row.name)
        _amountText = State(initialValue: row.amountInput)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("编辑目标").font(.headline)
            TextField("名称", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("金额 (元)", text: $amountText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 300)
    }

    private func submit() {
        do {
            try save(name, AmountText.parse(amountText) ?? 0)
            dismiss()
        } catch {
            errorMessage = error.message
        }
    }
}
