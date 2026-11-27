import SwiftUI
import WageCore

/// 目标管理 (PRD F8，设计稿 P3 目标管理 · 760)：攒钱队列、已完成两组，底部「新目标」。在今日概览窗口里推进来，页头的返回回到概览。
/// 攒钱队列整组可拖动排序【D6】，第一行是累计中 (进度条、累计额、预计完成)，其余排队中，见 `GoalQueueList`；
/// 已完成沉底、冻结只能删。编辑、删除在悬停时出现的按钮或右键菜单里，点整行不做任何事。
/// 没有任何目标时页头与底部按钮之间居中放一个大旗子图标和一行提示。
/// 校验与排序规则交给核心，失败时展示 `CommandError.message`；文字原样取自快照。
struct GoalsView: View {
    let content: GoalsContent
    /// 执行命令并刷新列表，校验失败时抛出。
    let send: (Command) throws(CommandError) -> Void
    /// 回到概览。
    let close: () -> Void

    /// 列表操作 (删除、拖动) 被核心拒绝时的提示，如列表过期时目标已不在。
    @State private var listError: String?
    /// 正在新建或编辑的目标；nil 时没有表单。
    @State private var form: GoalFormView.Mode?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader("目标", back: close, isRoot: true)
            if content.list.isEmpty {
                emptyState
            } else {
                ScrollBody {
                    groups.padding(Spacing.screen)
                }
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
        VStack(alignment: .leading, spacing: Spacing.s24) {
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
        }
    }

    /// 没有任何目标 (设计稿 Empty)：居中一个大旗子图标，下面一行提示，如「给自己定个目标吧」。
    private var emptyState: some View {
        VStack(spacing: Spacing.s14) {
            PhosphorIcon(.flagBanner, size: 56)
                .foregroundStyle(Palette.line)
                .accessibilityHidden(true)
            if let text = content.emptyText {
                Text(text).font(AppFont.body).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button { form = .create } label: { Label { Text("新目标") } icon: { PhosphorIcon(.plus) } }
                .buttonStyle(.primary(fullWidth: true, height: ControlHeight.footerButton))
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s12)
        .padding(.bottom, Spacing.screen)
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

/// 已完成的一行 (surface 底，整行 muted)，三行结构同攒钱队列 (`GoalRowLayout`)：对勾，名称与金额，满的 muted 进度条，达成日期。
/// 不可拖动 (AC-GOAL-10)。名称放不下时悬停在整行上横向滚动 (`HoverMarqueeText`)，悬停时第三行右端出删除按钮。
private struct CompletedGoalRowView: View {
    let row: CompletedGoalRow
    let delete: () -> Void

    @State private var hovering = false

    /// 名称一栏至少留多宽：内容区宽 266 (对勾比拖动手柄宽 2)，减去与金额的间距 8、最宽的合法金额「¥999998.99」(78)，
    /// 名称最多能留 180；留 170 (多留 10 的余量)，合法金额照样完整显示，上限出现之前存下的超大金额截断，名称仍露出十来个字。
    private static let nameMinWidth: CGFloat = 170

    var body: some View {
        GoalRowLayout(nameMinWidth: Self.nameMinWidth, track: GoalTrack(base: Palette.muted)) {
            PhosphorIcon(.checkCircle, size: 16)
                .foregroundStyle(Palette.money)
        } name: {
            HoverMarqueeText(row.name, isActive: hovering).font(AppFont.bodySemibold)
        } amount: {
            Text(row.amountText).font(AppFont.num(13))
        } caption: {
            Text(row.completedText).font(AppFont.small)
        } buttons: {
            if hovering {
                IconButton(systemName: "trash", help: "删除", action: delete)
            }
        }
        .foregroundStyle(Palette.muted)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r10))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("删除", role: .destructive, action: delete)
        }
    }
}
