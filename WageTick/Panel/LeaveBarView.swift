import SwiftUI
import WageCore

/// 请假表单的「请哪段」(设计稿 F6 · 时间条 · 760)：右上角时段说明 (「14:00 – 16:00 · 2 小时」)；
/// 整条为这天的计划上下班 (surface 底、line 描边、圆角 8、高 28)，饭点画成一块 line 色并标「饭点」；
/// 选中的一段 accentSoft 底、accent 1.5 描边，两头各一个把手 (14×40 白底、accent 描边、圆角 7、三道横纹)。
/// 下面每 10 分钟一根刻度 (整点更高)、几个时刻文字，再下面快捷的全天、前半天、后半天。
/// 拖把手改开始、结束，拖选中的一段整体平移；吸附与边界都交给核心的 `LeaveBar`，这里只把比例换成坐标。
struct LeaveBarView: View {
    let bar: LeaveBar
    @Binding var range: LeaveRange
    /// 整段平移开始时的时段：平移量按它算，免得每次吸附的误差累积。
    @State private var moveOrigin: LeaveRange?

    private static let trackHeight: CGFloat = 28
    private static let handleSize = CGSize(width: 14, height: 40)
    private static let space = "leaveBar"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.bottom, Spacing.s10)
            GeometryReader { geometry in
                track(width: geometry.size.width)
            }
            .frame(height: Self.handleSize.height)
            .coordinateSpace(.named(Self.space))
            ticks.frame(height: 6).padding(.top, Spacing.s10)
            labels.padding(.top, Spacing.s4)
            quickPicks.padding(.top, Spacing.s12)
        }
    }

    /// 「请哪段」与时段说明 (时段等宽 13/600 墨色，时长 12 muted)。
    private var header: some View {
        let title = bar.title(of: range)
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            FormLabel("请哪段")
            Spacer(minLength: Spacing.s8)
            Text(title.range).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.ink)
            Text("·").font(AppFont.caption).foregroundStyle(Palette.muted)
            Text(title.duration).font(AppFont.caption).foregroundStyle(Palette.muted)
        }
    }

    // MARK: 时间条

    /// 从下往上：底色、选中的一段的底色、饭点块 (选中范围盖住饭点时也看得见)、选中的描边、两个把手。
    private func track(width: CGFloat) -> some View {
        let x = { (time: TimeOfDay) in bar.position(of: time) * width }
        let start = x(range.start)
        let end = x(range.end)
        let inset = (Self.handleSize.height - Self.trackHeight) / 2
        let shape = RoundedRectangle(cornerRadius: Radius.r8)
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Palette.surface
                Palette.accentSoft
                    .frame(width: max(end - start, 0))
                    .offset(x: start)
                lunchBlock(width: width)
            }
            .frame(width: width, height: Self.trackHeight)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
            .offset(y: inset)
            Rectangle()
                .strokeBorder(Palette.accent, lineWidth: 1.5)
                .contentShape(Rectangle())
                .frame(width: max(end - start, 0), height: Self.trackHeight)
                .offset(x: start, y: inset)
                .gesture(moveGesture(width: width))
                .cursor(moveOrigin == nil ? .openHand : .closedHand)
            handle(.start, at: start, width: width)
            handle(.end, at: end, width: width)
        }
        .frame(width: width, height: Self.handleSize.height, alignment: .topLeading)
    }

    /// 饭点块 (line 色，与选中的一段重叠时略透出底下的选中色)，够宽时标「饭点」10。
    @ViewBuilder
    private func lunchBlock(width: CGFloat) -> some View {
        if let lunch = bar.lunch {
            let lunchWidth = (lunch.end - lunch.start) * width
            Palette.line.opacity(0.85)
                .overlay {
                    if lunchWidth >= 26 {
                        Text("饭点").font(AppFont.tiny).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                .frame(width: lunchWidth)
                .offset(x: lunch.start * width)
        }
    }

    /// 把手：中心对准时段的开始或结束。
    private func handle(_ handle: LeaveBar.Handle, at x: CGFloat, width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r7)
        return VStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().fill(Palette.accent).frame(width: 6, height: 1.5)
            }
        }
        .frame(width: Self.handleSize.width, height: Self.handleSize.height)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(Palette.accent, lineWidth: 1.5))
        .contentShape(Rectangle().inset(by: -Spacing.s4))
        .offset(x: x - Self.handleSize.width / 2)
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

    // MARK: 刻度与快捷

    /// 每 10 分钟一根刻度，整点高 6、其余高 3。
    private var ticks: some View {
        Canvas { context, size in
            var hours = Path()
            var minutes = Path()
            for tick in bar.ticks {
                let x = min(max(tick.position * size.width, 0.5), size.width - 0.5)
                if tick.isHour {
                    hours.move(to: CGPoint(x: x, y: 0))
                    hours.addLine(to: CGPoint(x: x, y: size.height))
                } else {
                    minutes.move(to: CGPoint(x: x, y: 0))
                    minutes.addLine(to: CGPoint(x: x, y: size.height / 2))
                }
            }
            context.stroke(hours, with: .color(Palette.muted.opacity(0.5)), lineWidth: 1)
            context.stroke(minutes, with: .color(Palette.muted.opacity(0.35)), lineWidth: 1)
        }
    }

    /// 时刻文字：第一个左对齐到起点，最后一个右对齐到终点，中间的居中对准刻度。
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

    /// 「快捷：」与全天、前半天、后半天 (surface 底、圆角 14、内边距 5×12、12/500 墨色)。
    private var quickPicks: some View {
        HStack(spacing: Spacing.s8) {
            Text("快捷：").font(AppFont.body).foregroundStyle(Palette.muted)
            ForEach(bar.quickPicks, id: \.title) { pick in
                Button { range = pick.range } label: {
                    Text(pick.title)
                        .font(AppFont.label)
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, Spacing.s5)
                        .padding(.horizontal, Spacing.s12)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r14))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.highlight(radius: Radius.r14))
            }
        }
    }
}
