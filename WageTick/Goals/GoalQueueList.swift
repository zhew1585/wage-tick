import SwiftUI
import WageCore

/// 攒钱队列 (PRD F8)：line 描边的卡片，整组按住一行上下拖动排序【D6】。
/// 第一行是累计中 (accent-soft 底，进度条、累计额 / 目标金额、预计完成，设计稿 P3 目标管理 · 760)，其余排队中。
/// 第一行的样子按「眼下排在第几」决定，拖到第一位的行即时显示成累计中，内容取快照里的 `asFirst` 预览。
/// 被拖的行实时跟着鼠标，其余行带动画让位，松手才把新顺序交给核心。
/// 用列表内的拖动手势而不是系统拖放 (`onDrag`)：系统拖放要生成拖拽图、走跨 App 的拖放流程，起拖慢、跟手差。
/// - 拖动距离在列表自己的坐标系 (`coordinateSpace`) 里量：在被拖的行里量的话，行一动坐标跟着动，会一抖一抖。
/// - 被拖的行不参与换位动画 (它的位移由偏移量直接抵掉)，只有让位的行做动画。
/// - 卡片不用 `clipShape` 裁圆角：行带 `zIndex` 时裁切会套到每一行上，悬停底色变成一块块圆角；改为首末行自己画外侧圆角。
/// 所有行同一个固定行高 (`QueueGoalRowView.height`)，按拖动距离算落点，不用逐行量尺寸。
struct GoalQueueList: View {
    let rows: [QueueGoalRow]
    let edit: (QueueGoalRow) -> Void
    let delete: (QueueGoalRow) -> Void
    /// 松手后攒钱队列的新顺序 (全部未完成目标)。
    let reorder: ([Int]) -> Void

    /// 正在拖的那行，以及它拖动开始时的位置和当前的拖动距离。
    @State private var drag: (id: Int, from: Int, offset: CGFloat)?

    /// 相邻两行的间距：行高加 1pt 分隔线。
    private static let slot = QueueGoalRowView.height + 1
    private static let space = "goalQueue"

    var body: some View {
        let order = currentOrder
        let shape = RoundedRectangle(cornerRadius: Radius.card)
        VStack(spacing: 0) {
            ForEach(Array(order.enumerated()), id: \.element.id) { index, row in
                if index > 0 { CardDivider() }
                let isDragged = drag?.id == row.id
                QueueGoalRowView(
                    row: row,
                    isFirst: index == 0,
                    isLast: index == order.count - 1,
                    state: isDragged ? .dragging : (drag == nil ? .idle : .othersDragging),
                    edit: { edit(row) },
                    delete: { delete(row) }
                )
                .offset(y: isDragged ? draggedOffset(at: index) : 0)
                .zIndex(isDragged ? 1 : 0)
                .transaction { if isDragged { $0.animation = nil } }
                .gesture(dragGesture(for: row))
            }
        }
        .animation(.easeOut(duration: 0.15), value: order.map(\.id))
        .coordinateSpace(name: Self.space)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
    }

    /// 拖动中按落点临时换过位置的顺序；没在拖时就是核心给的顺序。
    private var currentOrder: [QueueGoalRow] {
        guard let drag, let from = rows.firstIndex(where: { $0.id == drag.id }) else { return rows }
        var order = rows
        let moved = order.remove(at: from)
        order.insert(moved, at: target(for: drag))
        return order
    }

    /// 按拖动距离算出的落点，夹在列表首尾之间。
    private func target(for drag: (id: Int, from: Int, offset: CGFloat)) -> Int {
        let steps = Int((drag.offset / Self.slot).rounded())
        return min(max(drag.from + steps, 0), rows.count - 1)
    }

    /// 被拖的行：抵掉它在临时顺序里已经挪动的格数，保持贴着鼠标。
    private func draggedOffset(at index: Int) -> CGFloat {
        guard let drag else { return 0 }
        return drag.offset - CGFloat(index - drag.from) * Self.slot
    }

    /// 拖动距离夹在列表范围内：被拖的行最多到第一行或最后一行的位置，不会拖出卡片。
    private func clamped(_ translation: CGFloat) -> CGFloat {
        guard let drag else { return translation }
        let up = -CGFloat(drag.from) * Self.slot
        let down = CGFloat(rows.count - 1 - drag.from) * Self.slot
        return min(max(translation, up), down)
    }

    private func dragGesture(for row: QueueGoalRow) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil, let from = rows.firstIndex(where: { $0.id == row.id }) {
                    drag = (row.id, from, 0)
                }
                drag?.offset = clamped(value.translation.height)
            }
            .onEnded { _ in
                guard drag != nil else { return }
                let ids = currentOrder.map(\.id)
                drag = nil
                if ids != rows.map(\.id) { reorder(ids) }
            }
    }
}

/// 攒钱队列的一行，固定行高。`isFirst` 时是累计中的样子，否则是排队中。
/// 悬停显示编辑、删除按钮 (排队中的行另叠一层 surface 底)，光标是张开的手 (可拖动排序)；拖动时浮起成一张带投影的小卡。
/// 点整行不做任何事，编辑走铅笔按钮或右键菜单。
private struct QueueGoalRowView: View {
    enum DragState {
        case idle
        /// 这一行正被拖动。
        case dragging
        /// 别的行正被拖动：鼠标划过也不亮悬停底色、不出按钮。
        case othersDragging
    }

    let row: QueueGoalRow
    /// 排在第一位 (累计中)：首行也画卡片上侧圆角。
    let isFirst: Bool
    /// 排在最后：画卡片下侧圆角。
    let isLast: Bool
    let state: DragState
    let edit: () -> Void
    let delete: () -> Void

    /// 行高固定，排序时按它算落点；累计中的三行信息 (名称与金额、进度条、预计完成) 要在这个高度内排下。
    static let height: CGFloat = 76

    private static let trackHeight: CGFloat = 6
    private static let dragRadius = Radius.r10

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s10) {
            handle
            if isFirst { accumulating } else { queued }
        }
        .padding(.horizontal, Spacing.s14)
        .frame(height: Self.height)
        .background { background }
        .contentShape(Rectangle())
        .cursor(state == .dragging ? .closedHand : .openHand)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("编辑", action: edit)
            Button("删除", role: .destructive, action: delete)
        }
    }

    private var handle: some View {
        PhosphorIcon(.list, size: 14)
            .foregroundStyle(isFirst ? Palette.accent : Palette.muted)
            .help("拖动调整顺序，排在第一个的就是累计中")
    }

    private var showsButtons: Bool { hovering && state == .idle }

    @ViewBuilder
    private var buttons: some View {
        if showsButtons {
            IconButton(systemName: "pencil", help: "编辑", action: edit)
            IconButton(systemName: "trash", help: "删除", action: delete)
        }
    }

    /// 累计中：名称与「累计中」标记、累计额 / 目标金额；进度条；预计完成。
    private var accumulating: some View {
        let card = row.asFirst
        return VStack(alignment: .leading, spacing: Spacing.s6) {
            HStack(spacing: Spacing.s6) {
                Text(card.name).font(AppFont.ui(14, .bold)).foregroundStyle(Palette.ink).lineLimit(1)
                Text("累计中")
                    .font(AppFont.chip)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, Spacing.s6)
                    .padding(.vertical, Spacing.s1)
                    .background(Palette.card, in: Capsule())
                    .fixedSize()
                Spacer(minLength: Spacing.s4)
                buttons
                amount(card)
            }
            track(card.progress)
            Text(card.estimate).font(AppFont.small).foregroundStyle(Palette.muted).lineLimit(1)
        }
    }

    /// 排队中：名称与「排队中」，右边目标金额。
    private var queued: some View {
        HStack(spacing: Spacing.s10) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(row.name).font(AppFont.bodySemibold).foregroundStyle(Palette.ink).lineLimit(1)
                Text("排队中").font(AppFont.small).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: Spacing.s8)
            buttons
            Text(row.amountText).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.ink)
        }
    }

    /// accent 大号累计额，后跟小号「/ 目标金额」。
    private func amount(_ card: ActiveGoalCard) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
            Text(card.accumulatedText).font(AppFont.num(15, .bold)).foregroundStyle(Palette.accent)
            Text("/ \(card.targetText)").font(AppFont.numSmall).foregroundStyle(Palette.muted)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func track(_ progress: Double) -> some View {
        Capsule()
            .fill(Palette.card)
            .frame(height: Self.trackHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
    }

    @ViewBuilder
    private var background: some View {
        switch state {
        case .dragging:
            RoundedRectangle(cornerRadius: Self.dragRadius)
                .fill(isFirst ? Palette.accentSoft : Palette.card)
                .overlay(RoundedRectangle(cornerRadius: Self.dragRadius).strokeBorder(Palette.line, lineWidth: 1))
                .shadow(color: Palette.shadow, radius: 6, y: 2)
        case _ where isFirst:
            outerShape.fill(Palette.accentSoft)
        case .idle where hovering:
            outerShape.fill(Palette.surface)
        default:
            Color.clear
        }
    }

    /// 首行带卡片上侧圆角、末行带下侧圆角，和卡片外框贴合。
    private var outerShape: UnevenRoundedRectangle {
        let radius = Radius.card
        return UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? radius : 0,
            bottomLeadingRadius: isLast ? radius : 0,
            bottomTrailingRadius: isLast ? radius : 0,
            topTrailingRadius: isFirst ? radius : 0
        )
    }
}
