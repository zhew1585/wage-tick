import SwiftUI
import WageCore

/// 请假表单的「请哪段」时间条 (设计稿「弹窗-请假」)：整条为这天的计划上下班 (surface 底、圆角 12、高 44)，
/// 饭点一块 line 色并标「饭点」；请假段墨色、中间高亮黄「请假」，两头各一个黄色把手。
/// 下面几个时刻文字，再下面一排快捷：全天、前半天、后半天，和「自己拖」(时段不是快捷项时选中，只是标示)。
/// 拖把手改开始、结束，拖墨色的一段整体平移；吸附与边界都交给核心的 `LeaveBar`，这里只把比例换成坐标。
struct LeaveBarView: View {
    let bar: LeaveBar
    @Binding var range: LeaveRange
    /// 整段平移开始时的时段：平移量按它算，免得每次吸附的误差累积。
    @State private var moveOrigin: LeaveRange?

    private static let trackHeight: CGFloat = 44
    /// 黄色把手 (画在请假段里面贴着两头) 与它的拖动区 (以端点为中心)。
    private static let gripSize = CGSize(width: 5, height: 18)
    private static let gripInset: CGFloat = 5
    private static let handleHitWidth: CGFloat = 22
    private static let space = "leaveBar"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                track(width: geometry.size.width)
            }
            .frame(height: Self.trackHeight)
            .coordinateSpace(.named(Self.space))
            labels.padding(.top, Spacing.s8)
            quickPicks.padding(.top, Spacing.s12)
        }
    }

    // MARK: 时间条

    /// 从下往上：底色、请假段 (墨色与「请假」)、饭点块 (请假段盖住饭点时也看得见)、把手。
    private func track(width: CGFloat) -> some View {
        let x = { (time: TimeOfDay) in bar.position(of: time) * width }
        let start = x(range.start)
        let end = x(range.end)
        let selected = max(end - start, 0)
        return ZStack(alignment: .topLeading) {
            Palette.surface
            Palette.ink
                .overlay {
                    if selected >= 44 {
                        Text("请假").font(AppFont.ui(13, .bold)).foregroundStyle(Palette.highlight).lineLimit(1)
                    }
                }
                .frame(width: selected)
                .offset(x: start)
                .contentShape(Rectangle())
                .gesture(moveGesture(width: width))
                .cursor(moveOrigin == nil ? .openHand : .closedHand)
            lunchBlock(width: width)
            handle(.start, at: start, width: width)
            handle(.end, at: end, width: width)
        }
        .frame(width: width, height: Self.trackHeight, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.r12))
    }

    /// 饭点块 (line 色)，够宽时标「饭点」12；不接收点击，拖请假段时穿透过去。
    @ViewBuilder
    private func lunchBlock(width: CGFloat) -> some View {
        if let lunch = bar.lunch {
            let lunchWidth = (lunch.end - lunch.start) * width
            Palette.line
                .overlay {
                    if lunchWidth >= 28 {
                        Text("饭点").font(AppFont.caption).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                .frame(width: lunchWidth)
                .offset(x: lunch.start * width)
                .allowsHitTesting(false)
        }
    }

    /// 把手：黄色小竖条贴在请假段里面，拖动区以端点为中心。
    private func handle(_ handle: LeaveBar.Handle, at x: CGFloat, width: CGFloat) -> some View {
        let gripOffset = handle == .start ? Self.gripInset : -Self.gripInset
        return Capsule()
            .fill(Palette.highlight)
            .frame(width: Self.gripSize.width, height: Self.gripSize.height)
            .offset(x: gripOffset + (handle == .start ? Self.gripSize.width / 2 : -Self.gripSize.width / 2))
            .frame(width: Self.handleHitWidth, height: Self.trackHeight)
            .contentShape(Rectangle())
            .offset(x: x - Self.handleHitWidth / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                    range = bar.dragging(handle, of: range, to: value.location.x / width)
                }
            )
            .cursor(.columnResize)
            .accessibilityLabel(handle == .start ? "请假开始" : "请假结束")
    }

    private func moveGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let origin = moveOrigin ?? range
                moveOrigin = origin
                range = bar.moving(origin, by: value.translation.width / width)
            }
            .onEnded { _ in moveOrigin = nil }
    }

    // MARK: 时刻与快捷

    /// 时刻文字 (等宽 11 muted)：第一个左对齐到起点，最后一个右对齐到终点，中间的居中对准位置。
    private var labels: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(bar.labels.enumerated()), id: \.offset) { index, label in
                    let alignment: Alignment = index == 0 ? .leading : (index == bar.labels.count - 1 ? .trailing : .center)
                    Text(label.text)
                        .font(AppFont.numSmall)
                        .foregroundStyle(Palette.muted)
                        .fixedSize()
                        .frame(width: width, alignment: alignment)
                        .offset(x: alignment == .center ? (label.position - 0.5) * width : 0)
                }
            }
        }
        .frame(height: 14)
    }

    /// 快捷：全天、前半天、后半天，与时段相同的那个选中；都不是时「自己拖」选中 (点不动，只是标示)。
    private var quickPicks: some View {
        let custom = !bar.quickPicks.contains { $0.range == range }
        return HStack(spacing: Spacing.s8) {
            ForEach(bar.quickPicks, id: \.title) { pick in
                Button(pick.title) { range = pick.range }
                    .buttonStyle(BoldChoiceStyle(selected: pick.range == range))
            }
            Button("自己拖") {}
                .buttonStyle(BoldChoiceStyle(selected: custom))
                .disabled(true)
                .help("拖时间条上的黄色把手，或拖整段平移")
        }
    }
}
