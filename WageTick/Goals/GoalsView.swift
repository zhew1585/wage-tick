import SwiftUI
import WageCore

/// 目标管理 (PRD F8，设计稿 P3)：攒钱队列、已完成两组，底部「新目标」。
/// 攒钱队列整组可拖动排序【D6】，第一行是累计中 (进度条、累计额、预计完成)，其余排队中，见 `GoalQueueList`；
/// 已完成沉底、冻结只能删。编辑、删除在悬停时出现的按钮或右键菜单里，点整行不做任何事。
/// 校验与排序规则交给核心，失败时展示 `CommandError.message`；文字原样取自快照。
struct GoalsView: View {
    let content: GoalsContent
    /// 执行命令并刷新列表，校验失败时抛出。
    let send: (Command) throws(CommandError) -> Void
    let close: () -> Void

    /// 列表操作 (删除、拖动) 被核心拒绝时的提示，如列表过期时目标已不在。
    @State private var listError: String?
    /// 正在新建或编辑的目标；nil 时没有表单。
    @State private var form: GoalFormView.Mode?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("目标", back: close)
            ScrollBody {
                groups
                    .padding(.horizontal, Spacing.screen)
                    .padding(.vertical, Spacing.s18)
            }
            footer
        }
        .frame(width: Spacing.pageWidth)
        .sheet(item: $form) { mode in
            GoalFormView(mode: mode, save: { (command: Command) throws(CommandError) in try send(command) }, dismiss: { form = nil })
        }
    }

    @ViewBuilder
    private var groups: some View {
        let list = content.list
        VStack(alignment: .leading, spacing: Spacing.s20) {
            if !list.queue.isEmpty {
                group("攒钱队列", count: list.queue.count) {
                    GoalQueueList(
                        rows: list.queue,
                        edit: { form = .edit($0) },
                        delete: { perform(.deleteGoal(id: $0.id)) },
                        reorder: { perform(.reorderGoals(ids: $0)) }
                    )
                }
            }
            if !list.completed.isEmpty {
                group("已完成", count: list.completed.count) {
                    VStack(spacing: Spacing.s8) {
                        ForEach(list.completed) { row in
                            CompletedGoalRowView(row: row, delete: { perform(.deleteGoal(id: row.id)) })
                        }
                    }
                }
            }
            // 没有任何目标时只放一个大旗子图标，文案留给悬停提示和读屏。
            if list.isEmpty, let emptyText = content.emptyText {
                PhosphorIcon(.flagBanner, size: 56)
                    .foregroundStyle(Palette.line)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 180)
                    .help(emptyText)
                    .accessibilityElement()
                    .accessibilityLabel(emptyText)
            }
        }
    }

    private func group(_ title: String, count: Int, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            GroupLabel(title: title, count: count)
            content()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            if let listError {
                Text(listError).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            Button { form = .create } label: { Label("新目标", systemImage: "plus") }
                .buttonStyle(.primary(fullWidth: true))
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.bottom, Spacing.s18)
    }

    /// 列表上直接发出的命令，失败时在底部按钮上方提示。
    private func perform(_ command: Command) {
        do {
            try send(command)
            listError = nil
        } catch {
            listError = error.message
        }
    }
}

/// 已完成的一行 (surface 底，整行 muted)：对勾、名称、达成日期，右边金额。不可拖动 (AC-GOAL-10)。
private struct CompletedGoalRowView: View {
    let row: CompletedGoalRow
    let delete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(Palette.money)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(row.name).font(AppFont.bodySemibold).lineLimit(1)
                Text(row.completedText).font(AppFont.small)
            }
            Spacer(minLength: Spacing.s8)
            if hovering {
                IconButton(systemName: "trash", help: "删除", action: delete)
            }
            Text(row.amountText).font(AppFont.num(13))
        }
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, Spacing.s14)
        .padding(.vertical, Spacing.s10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r10))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("删除", role: .destructive, action: delete)
        }
    }
}
