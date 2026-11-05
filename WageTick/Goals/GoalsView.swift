import SwiftUI
import WageCore

/// 目标管理 (PRD F8)：上方新建表单 (名称、金额)，下方目标列表 (累计中、排队中、已完成)。
/// 列表按累计中、排队中、已完成分三组，可编辑、删除，排队中一组内可拖动排序；能否编辑、拖动取自快照的 `GoalRow`。
/// 校验与排序规则交给核心，失败时展示 `CommandError.message`；列表文字原样取自快照。
struct GoalsView: View {
    let content: GoalsContent
    /// 执行命令并刷新列表，校验失败时抛出。
    let send: (Command) throws(CommandError) -> Void

    @State private var name = ""
    @State private var amountText = ""
    @State private var errorMessage: String?
    /// 列表操作 (删除、拖动) 被核心拒绝时的提示，如列表过期时目标已不在。
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

    /// 三组 (PRD F8)：只有排队中一组可拖动，累计中单独一组，拖不到它前面【D6】。空的组不显示。
    private var list: some View {
        List {
            section("累计中", rows: rows(.accumulating))
            if !rows(.queued).isEmpty {
                Section("排队中") {
                    ForEach(rows(.queued), content: rowView)
                        .onMove(perform: move)
                }
            }
            section("已完成", rows: rows(.completed))
        }
        .listStyle(.plain)
        .frame(minHeight: 220)
    }

    @ViewBuilder
    private func section(_ title: String, rows: [GoalRow]) -> some View {
        if !rows.isEmpty {
            Section(title) { ForEach(rows, content: rowView) }
        }
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

    private func rows(_ kind: GoalRow.Kind) -> [GoalRow] { content.rows.filter { $0.kind == kind } }

    /// 拖动后把队列的新顺序 (累计中在前，排队中按拖动后的顺序) 交给核心。
    private func move(from source: IndexSet, to destination: Int) {
        var queued = rows(.queued).map(\.id)
        queued.move(fromOffsets: source, toOffset: destination)
        perform(.reorderGoals(ids: rows(.accumulating).map(\.id) + queued))
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
            try send(.createGoal(name: name, amount: AmountText.parse(amountText) ?? 0))
        } catch {
            errorMessage = error.message
            return
        }
        name = ""
        amountText = ""
        errorMessage = nil
    }
}
