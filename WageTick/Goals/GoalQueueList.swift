import SwiftUI
import WageCore

/// 攒钱队列 (PRD F8，大胆版设计稿「目标-攒钱队列」)：第一个 (累计中) 是首页同款墨色大卡 (`BoldGoalCard`，右上「队列 1/N」)，
/// 其余排队中的一个一张描边卡 (橙色大序号、名称与预计、金额、拖拽手柄)。整组按住任一张上下拖动排序【D6】，拖到第一个的松手即成为累计中。
/// 被拖的卡实时跟着鼠标，其余卡带动画让位，松手才把新顺序交给核心；拖动中每张卡保持原来的样子 (大卡还是大卡)，松手后按新顺序重画。
/// 用列表内的拖动手势而不是系统拖放 (`onDrag`)：系统拖放要生成拖拽图、走跨 App 的拖放流程，起拖慢、跟手差。
/// - 拖动距离在列表自己的坐标系 (`coordinateSpace`) 里量：在被拖的卡里量的话，卡一动坐标跟着动，会一抖一抖。
/// - 大卡和小卡高度不同，每张卡量出自己的高度，按被拖卡的中心越过了哪几张卡的中心算落点。
/// 编辑、删除在悬停时出现的按钮或右键菜单里，点卡片本身不做任何事。
struct GoalQueueList: View {
    let rows: [QueueGoalRow]
    let edit: (QueueGoalRow) -> Void
    let delete: (QueueGoalRow) -> Void
    /// 松手后攒钱队列的新顺序 (全部未完成目标)。
    let reorder: ([Int]) -> Void

    /// 正在拖的那张，以及它拖动开始时的位置和当前的拖动距离。
    @State private var drag: (id: Int, from: Int, offset: CGFloat)?
    /// 每张卡量出来的高度，按目标编号。
    @State private var heights: [Int: CGFloat] = [:]

    private static let spacing = Spacing.s10
    private static let space = "goalQueue"

    var body: some View {
        let order = currentOrder
        VStack(spacing: Self.spacing) {
            ForEach(Array(order.enumerated()), id: \.element.id) { index, row in
                let isDragged = drag?.id == row.id
                card(row, index: index, isDragged: isDragged)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[row.id] = $0 }
                    .offset(y: isDragged ? draggedOffset(in: order) : 0)
                    .zIndex(isDragged ? 1 : 0)
                    .transaction { if isDragged { $0.animation = nil } }
                    .gesture(dragGesture(for: row))
            }
        }
        .animation(.easeOut(duration: 0.15), value: order.map(\.id))
        .coordinateSpace(name: Self.space)
    }

    /// 累计中 (核心给的第一个) 画大卡，其余画描边卡，序号按眼下 (拖动中临时) 的位置。
    @ViewBuilder
    private func card(_ row: QueueGoalRow, index: Int, isDragged: Bool) -> some View {
        let state: QueueCardState = isDragged ? .dragging : (drag == nil ? .idle : .othersDragging)
        if row.id == rows.first?.id {
            AccumulatingGoalCard(row: row, total: rows.count, state: state, edit: { edit(row) }, delete: { delete(row) })
        } else {
            QueuedGoalCardView(row: row, number: index + 1, state: state, edit: { edit(row) }, delete: { delete(row) })
        }
    }

    /// 拖动中按落点临时换过位置的顺序；没在拖时就是核心给的顺序。
    private var currentOrder: [QueueGoalRow] {
        guard let drag, let from = rows.firstIndex(where: { $0.id == drag.id }) else { return rows }
        var order = rows
        let moved = order.remove(at: from)
        order.insert(moved, at: target(for: drag))
        return order
    }

    private func height(_ row: QueueGoalRow) -> CGFloat {
        heights[row.id] ?? QueuedGoalCardView.height
    }

    /// 核心给的顺序里每张卡的上沿。
    private var tops: [CGFloat] {
        rows.indices.map { index in
            rows[..<index].reduce(0) { $0 + height($1) + Self.spacing }
        }
    }

    /// 落点：被拖卡此刻的中心越过了几张别的卡的中心，就排在第几。
    private func target(for drag: (id: Int, from: Int, offset: CGFloat)) -> Int {
        let tops = tops
        let center = tops[drag.from] + height(rows[drag.from]) / 2 + drag.offset
        return rows.indices.filter { $0 != drag.from && tops[$0] + height(rows[$0]) / 2 < center }.count
    }

    /// 被拖的卡：抵掉它在临时顺序里的新位置，保持贴着鼠标。
    private func draggedOffset(in order: [QueueGoalRow]) -> CGFloat {
        guard let drag, let index = order.firstIndex(where: { $0.id == drag.id }) else { return 0 }
        let laidOut = order[..<index].reduce(0) { $0 + height($1) + Self.spacing }
        return tops[drag.from] + drag.offset - laidOut
    }

    /// 拖动距离夹在列表范围内：被拖的卡最多到最上或最下，不会拖出列表。
    private func clamped(_ translation: CGFloat, from: Int) -> CGFloat {
        let tops = tops
        guard let last = rows.indices.last else { return translation }
        let bottom = tops[last] + height(rows[last]) - height(rows[from])
        return min(max(translation, -tops[from]), bottom - tops[from])
    }

    private func dragGesture(for row: QueueGoalRow) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil, let from = rows.firstIndex(where: { $0.id == row.id }) {
                    drag = (row.id, from, 0)
                }
                if let from = drag?.from {
                    drag?.offset = clamped(value.translation.height, from: from)
                }
            }
            .onEnded { _ in
                guard drag != nil else { return }
                let ids = currentOrder.map(\.id)
                drag = nil
                if ids != rows.map(\.id) { reorder(ids) }
            }
    }
}

/// 一张卡在拖动中的状态。
private enum QueueCardState {
    case idle
    /// 这一张正被拖动。
    case dragging
    /// 别的卡正被拖动：鼠标划过也不出按钮。
    case othersDragging
}

/// 累计中目标的墨色大卡：首页同款 `BoldGoalCard`，右上写「队列 1/N」；悬停时右上换成编辑、删除按钮。光标是张开的手 (可拖动排序)。
private struct AccumulatingGoalCard: View {
    let row: QueueGoalRow
    let total: Int
    let state: QueueCardState
    let edit: () -> Void
    let delete: () -> Void

    @State private var hovering = false

    var body: some View {
        let showsButtons = hovering && state == .idle
        BoldGoalCard(goal: row.asFirst, trailing: showsButtons ? nil : "队列 1/\(total)")
            .overlay(alignment: .topTrailing) {
                if showsButtons {
                    HStack(spacing: Spacing.s10) {
                        IconButton(systemName: "pencil", help: "编辑", color: .white.opacity(0.7), action: edit)
                        IconButton(systemName: "trash", help: "删除", color: .white.opacity(0.7), action: delete)
                    }
                    .padding(.top, Spacing.s16)
                    .padding(.trailing, Spacing.s16)
                }
            }
            .shadow(color: state == .dragging ? Palette.ink.opacity(0.25) : .clear, radius: 10, y: 4)
            .contentShape(Rectangle())
            .cursor(state == .dragging ? .closedHand : .openHand)
            .onHover { hovering = $0 }
            .contextMenu {
                Button("编辑", action: edit)
                Button("删除", role: .destructive, action: delete)
            }
            .help("拖动调整顺序，排在第一个的就是累计中")
    }
}

/// 排队中目标的描边卡 (高 58、圆角 16、墨色描边)：橙色大序号 (02、03…)、名称与「排队中 · 预计 11月26日」、金额、拖拽手柄。
/// 悬停时金额前出现编辑、删除按钮；拖动时浮起一层投影。
private struct QueuedGoalCardView: View {
    let row: QueueGoalRow
    /// 眼下排第几 (从 1 起)。
    let number: Int
    let state: QueueCardState
    let edit: () -> Void
    let delete: () -> Void

    static let height: CGFloat = 58

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r16)
        HStack(spacing: Spacing.s10) {
            Text(String(format: "%02d", number))
                .font(AppFont.heavy(22))
                .foregroundStyle(Palette.accent)
                .frame(minWidth: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(row.name).font(AppFont.ui(14, .bold)).foregroundStyle(Palette.ink)
                Text(row.estimate).font(AppFont.small).foregroundStyle(Palette.muted)
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.s4)
            if hovering && state == .idle {
                IconButton(systemName: "pencil", help: "编辑", action: edit)
                IconButton(systemName: "trash", help: "删除", action: delete)
            }
            Text(BoldNumber.grouped(row.amountText)).font(AppFont.heavy(15)).foregroundStyle(Palette.ink).lineLimit(1).fixedSize()
            PhosphorIcon(.GoalIcon.dotsSixVertical, size: 14).foregroundStyle(Palette.muted)
        }
        .padding(.leading, Spacing.s14)
        .padding(.trailing, Spacing.s12)
        .frame(height: Self.height)
        .background(Palette.bg, in: shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: 1))
        .shadow(color: state == .dragging ? Palette.shadow : .clear, radius: 8, y: 3)
        .contentShape(shape)
        .cursor(state == .dragging ? .closedHand : .openHand)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("编辑", action: edit)
            Button("删除", role: .destructive, action: delete)
        }
        .help("拖动调整顺序，排在第一个的就是累计中")
    }
}
