import SwiftUI
import WageCore

/// 目标管理 (PRD F8)：上方新建表单 (名称、金额)，下方目标列表。
/// 校验交给核心，失败时展示 `CommandError.message`；列表文字原样取自快照的 `GoalRow`。
struct GoalsView: View {
    let content: GoalsContent
    let create: (String, Decimal) throws(CommandError) -> Void

    @State private var name = ""
    @State private var amountText = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            form
            Divider()
            list
        }
        .padding(20)
        .frame(width: 360)
        .frame(minHeight: 280, alignment: .top)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("新目标").font(.headline)
            TextField("名称，如 Switch 2", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("金额 (元)", text: $amountText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                Button("新建", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        if content.rows.isEmpty {
            Text("还没有目标").foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(content.rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).font(.body.weight(.medium))
                            Text(row.detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        Text(row.statusLabel).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func submit() {
        do {
            try create(name, parsedAmount ?? 0)
        } catch {
            errorMessage = error.message
            return
        }
        name = ""
        amountText = ""
        errorMessage = nil
    }

    /// 只认纯数字写法，其他写法视为未填；大于 0 等规则交给核心的 `Validation`。
    private var parsedAmount: Decimal? {
        let text = amountText.trimmingCharacters(in: .whitespaces)
        guard text.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}
