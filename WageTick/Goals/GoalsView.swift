import SwiftUI
import WageCore

/// 目标管理 (PRD F8)：上方新建表单 (名称、金额)，下方目标列表 (累计中、排队中、已完成)。
/// 列表可编辑、删除，排队中目标可拖动排序；能否编辑、拖动取自快照的 `GoalRow`。
/// 校验与排序规则交给核心，失败时展示 `CommandError.message`；列表文字原样取自快照。
struct GoalsView: View {
    let content: GoalsContent
    /// 执行命令并刷新列表，校验失败时抛出。
    let send: (Command) throws(CommandError) -> Void

    @State private var name = ""
    @State private var amountText = ""
    @State private var errorMessage: String?
    /// 列表操作 (删除、拖动) 被核心拒绝时的提示，如把排队中目标拖到累计中之前【D6】。
    @State private var listError: String?
    /// 正在编辑的目标；nil 时没有编辑表单。
    @State private var editing: GoalRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            form
            if !content.rows.isEmpty {
                Divider()
                list
                if let listError {
                    Text(listError).foregroundStyle(.red).font(.callout)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
        .frame(minHeight: 280, alignment: .top)
        .sheet(item: $editing) { row in
            GoalEditView(
                row: row,
                save: { (name: String, amount: Decimal) throws(CommandError) in
                    try send(.editGoal(id: row.id, name: name, amount: amount))
                },
                dismiss: { editing = nil }
            )
        }
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

    /// 队列 (累计中 + 排队中) 一组可拖动，累计中那一行禁止拖动；拖到累计中之前由核心拒绝。已完成另一组。
    private var list: some View {
        List {
            ForEach(queueRows) { row in
                rowView(row).moveDisabled(!row.canReorder)
            }
            .onMove(perform: move)
            ForEach(completedRows, content: rowView)
        }
        .listStyle(.plain)
        .frame(minHeight: 220)
    }

    private func rowView(_ row: GoalRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.body.weight(.medium))
                Text(row.detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Text(row.statusLabel).font(.caption).foregroundStyle(.secondary)
            if row.canEdit {
                Button { editing = row } label: { Image(systemName: "pencil") }
                    .help("编辑")
            }
            Button { perform(.deleteGoal(id: row.id)) } label: { Image(systemName: "trash") }
                .help("删除")
        }
        .buttonStyle(.borderless)
    }

    private var queueRows: [GoalRow] { content.rows.filter { $0.kind != .completed } }
    private var completedRows: [GoalRow] { content.rows.filter { $0.kind == .completed } }

    /// 拖动后把队列的新顺序原样交给核心。
    private func move(from source: IndexSet, to destination: Int) {
        var ids = queueRows.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        perform(.reorderGoals(ids: ids))
    }

    /// 列表上直接发出的命令，失败时在列表下方提示。
    private func perform(_ command: Command) {
        do {
            try send(command)
            listError = nil
        } catch {
            listError = error.message
        }
    }

    private func submit() {
        do {
            try send(.createGoal(name: name, amount: Self.parseAmount(amountText) ?? 0))
        } catch {
            errorMessage = error.message
            return
        }
        name = ""
        amountText = ""
        errorMessage = nil
    }

    /// 金额输入框：只认纯数字写法，其他写法视为未填 (nil)；大于 0 等规则交给核心的 `Validation`。
    static func parseAmount(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.wholeMatch(of: /[0-9]+(\.[0-9]+)?/) != nil else { return nil }
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }
}
