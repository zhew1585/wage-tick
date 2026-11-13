import SwiftUI
import WageCore

/// 目标页 (PRD F8，大胆版设计稿「目标-攒钱队列」「目标-还没有目标」)：按 `content.route` 显示攒钱队列、已到手或目标表单。
/// 攒钱队列页：橙色头图 (排队中的目标个数、全部攒完的预计、握拳小牛)，下面是攒钱队列 (`GoalQueueList`，可拖动排序、编辑、删除)，
/// 头图随滚动收起；底部固定「已到手 N」(有已完成目标时) 与「再想要一个」。队列为空时头图写 0，中间是空状态，按钮换成「定个目标」。
/// 校验与排序规则交给核心，失败时展示 `CommandError.message`；文字原样取自快照。
struct GoalsView: View {
    let content: GoalsContent
    /// 执行命令并刷新列表，校验失败时抛出。
    let send: (Command) throws(CommandError) -> Void
    /// 头图上的「返回」：退回今日概览。
    let close: () -> Void

    /// 列表操作 (删除、拖动) 被核心拒绝时的提示，如列表过期时目标已不在。
    @State private var listError: String?

    /// 攒钱队列在最底下，已到手、目标表单从右边推进来盖在上面；返回时往右滑出去。
    var body: some View {
        ZStack {
            queuePage
            switch content.route {
            case .queue:
                EmptyView()
            case .earned:
                GoalEarnedView(list: content.list, back: { content.route = .queue }, delete: { perform(.deleteGoal(id: $0.id)) })
                    .background(Palette.bg)
                    .pushed()
            case .form(let mode):
                GoalFormView(
                    mode: mode,
                    position: position(for: mode),
                    save: { (command: Command) throws(CommandError) in try send(command) },
                    dismiss: { content.route = .queue }
                )
                // 每次打开都是新的表单 (名称、金额清空)，不复用上一次还没退场完的那个。
                .id(content.formSession)
                .background(Palette.bg)
                .pushed()
            }
        }
        .animation(.push, value: content.route)
        .frame(width: Spacing.pageWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.bg)
    }

    private var queue: [QueueGoalRow] { content.list.queue }

    private var queuePage: some View {
        VStack(spacing: 0) {
            CollapsingHeroScroll { collapse in
                hero(collapse: collapse)
            } content: {
                if queue.isEmpty {
                    emptyState
                } else {
                    GoalQueueList(
                        rows: queue,
                        edit: { content.route = .form(.edit($0)) },
                        delete: { perform(.deleteGoal(id: $0.id)) },
                        reorder: { perform(.reorderGoals(ids: $0)) }
                    )
                    .padding(EdgeInsets(top: Spacing.s18, leading: Spacing.screen, bottom: Spacing.s16, trailing: Spacing.screen))
                }
            }
            footer
        }
    }

    /// 橙色头图：「想要的都写下来」、排队中的目标个数、全部攒完的预计 (没法预计时不写)；队列为空时说明换成「先定一个小目标」。
    private func hero(collapse: CGFloat) -> some View {
        let count = "\(queue.count)"
        let unit = "个在排队"
        return BoldHero(
            theme: .orange,
            back: HeroBack(label: "返回", action: close),
            kicker: heroKicker("想要的都写下来", collapsed: unit, collapse: collapse),
            caption: queue.isEmpty ? "先定一个小目标" : content.list.queueFinishText,
            captionIcon: .flagBanner,
            cow: .pose(.excited),
            bubble: HeroBubbleContent(value: queue.isEmpty ? "想要啥？" : "一个一个来", numeric: false),
            collapse: collapse,
            compactValue: count
        ) {
            HeroCount(value: count, unit: unit, theme: .orange)
        }
    }

    /// 队列为空 (设计稿「目标-还没有目标」)：头图下面居中一个靶子图标、一句问话和一行小字。
    private var emptyState: some View {
        VStack(spacing: Spacing.s8) {
            PhosphorIcon(.GoalIcon.target, size: 28)
                .foregroundStyle(Palette.ink)
                .frame(width: 64, height: 64)
                .background(Palette.surface, in: Circle())
                .padding(.bottom, Spacing.s8)
            Text("还没有想要的东西？").font(AppFont.ui(15, .bold)).foregroundStyle(Palette.ink)
            Text("写一个，小牛帮你算哪天攒够").font(AppFont.caption).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 126)
    }

    /// 底部固定栏：左边描边「已到手 N」(有已完成目标时)，右边墨色「再想要一个」(队列为空时「定个目标」)。
    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            if let listError {
                Text(listError).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            HStack(spacing: Spacing.s10) {
                let completed = content.list.completed.count
                if completed > 0 {
                    Button { content.route = .earned } label: {
                        Label { Text("已到手 \(completed)") } icon: { PhosphorIcon(.GoalIcon.trophy) }
                    }
                    .buttonStyle(.pill(.outline, fullWidth: false))
                    .fixedSize()
                }
                Button { content.route = .form(.create) } label: {
                    Label { Text(queue.isEmpty ? "定个目标" : "再想要一个") } icon: { PhosphorIcon(.plus) }
                }
                .buttonStyle(.pill(.ink))
            }
        }
        .padding(EdgeInsets(top: Spacing.s12, leading: Spacing.screen, bottom: Spacing.screen, trailing: Spacing.screen))
    }

    /// 表单头图里的「排第 N 个」：新建排在队尾，编辑是这个目标眼下的位置。
    private func position(for mode: GoalFormView.Mode) -> Int {
        switch mode {
        case .create: queue.count + 1
        case .edit(let row): (queue.firstIndex { $0.id == row.id } ?? 0) + 1
        }
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
