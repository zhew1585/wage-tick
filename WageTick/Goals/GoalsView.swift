import SwiftUI
import UniformTypeIdentifiers
import WageCore

/// 目标管理 (PRD F8，设计稿 P3)：累计中、排队中、已完成三组，底部「新目标」。
/// 累计中是一张大卡 (进度条与预计完成取自快照的 `ActiveGoalCard`，与面板目标区同一份)；
/// 排队中一组可拖动排序【D6】，点一行编辑；已完成冻结只能删。删除在悬停时出现的垃圾桶或右键菜单里。
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
        let queued = rows(.queued)
        let completed = rows(.completed)
        VStack(alignment: .leading, spacing: Spacing.s20) {
            if let active = content.active, let row = rows(.accumulating).first {
                group("累计中", count: 1) {
                    ActiveGoalView(card: active, edit: { form = .edit(row) }, delete: { perform(.deleteGoal(id: row.id)) })
                }
            }
            if !queued.isEmpty {
                group("排队中", count: queued.count) {
                    GoalQueueList(rows: queued, edit: { form = .edit($0) }, delete: { perform(.deleteGoal(id: $0.id)) }) { ids in
                        perform(.reorderGoals(ids: rows(.accumulating).map(\.id) + ids))
                    }
                }
            }
            if !completed.isEmpty {
                group("已完成", count: completed.count) {
                    VStack(spacing: Spacing.s8) {
                        ForEach(completed) { row in
                            CompletedGoalRow(row: row, delete: { perform(.deleteGoal(id: row.id)) })
                        }
                    }
                }
            }
            if content.rows.isEmpty, let emptyText = content.emptyText {
                Text(emptyText)
                    .font(AppFont.body)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s24)
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

    private func rows(_ kind: GoalRow.Kind) -> [GoalRow] { content.rows.filter { $0.kind == kind } }

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

/// 累计中目标的大卡 (accent-soft 底)：名称与编辑笔、累计额 / 目标金额、进度条、预计完成。
private struct ActiveGoalView: View {
    let card: ActiveGoalCard
    let edit: () -> Void
    let delete: () -> Void

    @State private var hovering = false

    private static let trackHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            HStack {
                Text(card.name).font(AppFont.ui(16, .bold)).foregroundStyle(Palette.ink).lineLimit(1)
                Spacer(minLength: Spacing.s8)
                if hovering {
                    IconButton(systemName: "trash", help: "删除", action: delete)
                }
                IconButton(systemName: "pencil", help: "编辑", action: edit)
            }
            amount
            track
            Text(card.estimate).font(AppFont.caption).foregroundStyle(Palette.muted)
        }
        .padding(Spacing.s16)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.card))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("编辑", action: edit)
            Button("删除", role: .destructive, action: delete)
        }
    }

    /// 「¥3000 / ¥10000」拆成大号累计额与小号目标金额，拆不开时整串原样展示。
    private var amount: some View {
        let parts = card.amountText.split(separator: " / ", maxSplits: 1).map(String.init)
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            Text(parts[0]).font(AppFont.num(20, .bold)).foregroundStyle(Palette.accent)
            if parts.count == 2 {
                Text("/ \(parts[1])").font(AppFont.numCaption).foregroundStyle(Palette.muted)
            }
        }
    }

    private var track: some View {
        Capsule()
            .fill(Palette.card)
            .frame(height: Self.trackHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: proxy.size.width * min(max(card.progress, 0), 1))
                }
            }
    }
}

/// 排队中一组：line 描边的卡片，每行左边拖动把手、名称，右边金额。
/// 按住一行上下拖动排序【D6】：被拖的行实时跟着鼠标，其余行带动画让位，松手才把新顺序交给核心。
/// 用列表内的拖动手势而不是系统拖放 (`onDrag`)：系统拖放要生成拖拽图、走跨 App 的拖放流程，起拖慢、跟手差。
/// 行高固定 (`QueuedGoalRow.height`)，按拖动距离算落点，不用逐行量尺寸。
private struct GoalQueueList: View {
    let rows: [GoalRow]
    let edit: (GoalRow) -> Void
    let delete: (GoalRow) -> Void
    /// 松手后排队中目标的新顺序。
    let reorder: ([Int]) -> Void

    /// 正在拖的那行，以及它拖动开始时的位置和当前的拖动距离。
    @State private var drag: (id: Int, from: Int, offset: CGFloat)?

    /// 相邻两行的间距：行高加 1pt 分隔线。
    private static let slot = QueuedGoalRow.height + 1

    var body: some View {
        let order = currentOrder
        CardBox(radius: Radius.card) {
            ForEach(Array(order.enumerated()), id: \.element.id) { index, row in
                if index > 0 { CardDivider() }
                QueuedGoalRow(row: row, isDragging: drag?.id == row.id, edit: { edit(row) }, delete: { delete(row) })
                    .offset(y: draggedOffset(for: row.id, at: index))
                    .zIndex(drag?.id == row.id ? 1 : 0)
                    .gesture(dragGesture(for: row))
            }
        }
        .animation(.easeOut(duration: 0.15), value: order.map(\.id))
    }

    /// 拖动中按落点临时换过位置的顺序；没在拖时就是核心给的顺序。
    private var currentOrder: [GoalRow] {
        guard let drag else { return rows }
        var order = rows
        guard let from = order.firstIndex(where: { $0.id == drag.id }) else { return rows }
        let moved = order.remove(at: from)
        order.insert(moved, at: target(for: drag))
        return order
    }

    /// 按拖动距离算出的落点，夹在列表首尾之间。
    private func target(for drag: (id: Int, from: Int, offset: CGFloat)) -> Int {
        let steps = Int((drag.offset / Self.slot).rounded())
        return min(max(drag.from + steps, 0), rows.count - 1)
    }

    /// 被拖的行：抵掉它在临时顺序里已经挪动的格数，保持贴着鼠标；其余行不偏移。
    private func draggedOffset(for id: Int, at index: Int) -> CGFloat {
        guard let drag, drag.id == id else { return 0 }
        return drag.offset - CGFloat(index - drag.from) * Self.slot
    }

    private func dragGesture(for row: GoalRow) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if drag == nil, let from = rows.firstIndex(where: { $0.id == row.id }) {
                    drag = (row.id, from, 0)
                }
                drag?.offset = value.translation.height
            }
            .onEnded { _ in
                guard let drag else { return }
                let ids = currentOrder.map(\.id)
                self.drag = nil
                if ids != rows.map(\.id) { reorder(ids) }
            }
    }
}

/// 排队中的一行：悬停叠一层底并显示编辑、删除按钮，光标是张开的手 (可拖动排序)，拖动时浮起。
/// 点整行不做任何事，编辑走铅笔按钮或右键菜单。
private struct QueuedGoalRow: View {
    let row: GoalRow
    let isDragging: Bool
    let edit: () -> Void
    let delete: () -> Void

    /// 行高固定，排序时按它算落点。
    static let height: CGFloat = 44

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 14, height: 14)
                .help("拖动调整顺序")
            Text(row.name).font(AppFont.bodySemibold).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: Spacing.s8)
            if hovering && !isDragging {
                IconButton(systemName: "pencil", help: "编辑", action: edit)
                IconButton(systemName: "trash", help: "删除", action: delete)
            }
            Text(row.detail).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, Spacing.s14)
        .frame(height: Self.height)
        .background(hovering || isDragging ? Palette.surface : Palette.card)
        .shadow(color: isDragging ? Palette.shadow : .clear, radius: 4, y: 2)
        .contentShape(Rectangle())
        .cursor(isDragging ? .closedHand : .openHand)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("编辑", action: edit)
            Button("删除", role: .destructive, action: delete)
        }
    }
}

/// 已完成的一行 (surface 底，整行 muted)：对勾、名称、达成日期，右边金额。
private struct CompletedGoalRow: View {
    let row: GoalRow
    let delete: () -> Void

    @State private var hovering = false

    var body: some View {
        let detail = CompletedDetail(row.detail)
        HStack(spacing: Spacing.s10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(Palette.money)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(row.name).font(AppFont.bodySemibold).lineLimit(1)
                if let date = detail.date {
                    Text(date).font(AppFont.small)
                }
            }
            Spacer(minLength: Spacing.s8)
            if hovering {
                IconButton(systemName: "trash", help: "删除", action: delete)
            }
            Text(detail.amount).font(AppFont.num(13))
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

/// 已完成目标的说明「¥500 · 2月11日达成」拆成金额 (放右边) 与日期 (放名称下)；拆不开时整串当金额。
private struct CompletedDetail {
    let amount: String
    let date: String?

    init(_ detail: String) {
        let parts = detail.split(separator: " · ", maxSplits: 1).map(String.init)
        amount = parts[0]
        date = parts.count == 2 ? parts[1] : nil
    }
}
