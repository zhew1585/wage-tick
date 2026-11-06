import AppKit
import SwiftUI

// 可点元素的统一交互反馈：悬停光标变手型，悬停、按下有颜色变化，不可用时都没有。颜色在 `Palette` 的「交互态」里。
//
// 用法，按元素选一种：
// - 主、次按钮：`.buttonStyle(.primary)` / `.secondary` (`ThemeButtonStyle`)，已内置。
// - 透明底的小按钮 (图标按钮、返回、列表行、文字链接)：`.buttonStyle(.highlight(radius: Radius.r6, outset: 4))`。
// - 选中态、描边等要自己画的 (分段控件、标签、日历格子)：`.buttonStyle(InteractiveButtonStyle { label, state in … })`。
// - 不是 Button 的可点元素 (挂 `onTapGesture` 的行)：`.hoverFeedback(cornerRadius: Radius.control)`。
// - 只要光标：`.pointingHandCursor()`；输入框外框点了会聚焦的：`.cursor(.iBeam)`。
// 文本输入框本身的 I 型光标由系统给，不用管。

/// 可点元素此刻的交互状态。不可用时悬停、按下都为 false。
struct InteractionState: Equatable {
    var isHovered = false
    var isPressed = false
    var isEnabled = true

    /// 叠在元素底色上的一层：按下 > 悬停 > 无。
    var overlay: Color {
        if isPressed { return Palette.pressedOverlay }
        if isHovered { return Palette.hoverOverlay }
        return .clear
    }
}

/// 自绘按钮的底座：读出悬停、按下、可用，交给 `style` 画；可用时悬停光标变手型。
struct InteractiveButtonStyle<Styled: View>: ButtonStyle {
    let style: @MainActor (ButtonStyleConfiguration.Label, InteractionState) -> Styled

    init(_ style: @escaping @MainActor (ButtonStyleConfiguration.Label, InteractionState) -> Styled) {
        self.style = style
    }

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButton(configuration: configuration, style: style)
    }
}

/// 单独成视图才能存悬停状态、读到 `isEnabled`。
private struct InteractiveButton<Styled: View>: View {
    let configuration: ButtonStyleConfiguration
    let style: @MainActor (ButtonStyleConfiguration.Label, InteractionState) -> Styled

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        let state = InteractionState(
            isHovered: isEnabled && isHovered,
            isPressed: isEnabled && configuration.isPressed,
            isEnabled: isEnabled
        )
        style(configuration.label, state)
            .onHover { isHovered = $0 }
            .pointingHandCursor(isEnabled)
    }
}

/// 透明底小按钮的反馈：悬停、按下时在圆角块里叠一层底色 (盖在内容上，自带底色的按钮也看得出)。
/// `outset`：底色比按钮内容向外多出的距离，小图标按钮靠它露出一圈底；只画不占位。
struct HighlightButtonStyle: ButtonStyle {
    var radius: CGFloat = Radius.r6
    var outset: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        InteractiveButtonStyle { label, state in
            label.overlay {
                RoundedRectangle(cornerRadius: radius)
                    .fill(state.overlay)
                    .padding(-outset)
                    .allowsHitTesting(false)
            }
        }
        .makeBody(configuration: configuration)
    }
}

extension ButtonStyle where Self == HighlightButtonStyle {
    static func highlight(radius: CGFloat = Radius.r6, outset: CGFloat = 0) -> HighlightButtonStyle {
        HighlightButtonStyle(radius: radius, outset: outset)
    }
}

extension View {
    /// 不是 Button 的可点元素 (挂 `onTapGesture` 的行) 的反馈：手型光标，悬停、按下时在圆角块里叠一层底色。
    /// `isEnabled` 为 false (这一行点不了) 时什么都不加。按下态与点击手势并行识别，不影响点击和里面的小按钮。
    /// `showsPress`：能拖走的行 (挂了 `onDrag`) 传 false，按下态的手势会抢走拖动，只留悬停反馈。
    func hoverFeedback(cornerRadius: CGFloat = 0, isEnabled: Bool = true, showsPress: Bool = true) -> some View {
        modifier(HoverFeedback(cornerRadius: cornerRadius, isEnabled: isEnabled, showsPress: showsPress))
    }

    /// 悬停时光标变成手型；`isActive` 为 false (不可用) 时不变。
    func pointingHandCursor(_ isActive: Bool = true) -> some View {
        cursor(.pointingHand, isActive: isActive)
    }

    /// 悬停时显示 `cursor`；`isActive` 为 false 时不变。
    func cursor(_ cursor: HoverCursor, isActive: Bool = true) -> some View {
        modifier(HoverCursorModifier(cursor: cursor, isActive: isActive))
    }
}

/// 悬停时换成的光标。
enum HoverCursor {
    /// 手型：可点的东西。
    case pointingHand
    /// I 型：点了会聚焦到输入框的区域。
    case iBeam
    /// 张开的手：可以按住拖动的东西 (排队目标的行)。
    case openHand
    /// 握住的手：正在拖动。
    case closedHand
    /// 左右箭头：可以左右拖的把手 (请假时间条)。
    case columnResize

    @available(macOS 15, *)
    fileprivate var pointerStyle: PointerStyle {
        switch self {
        case .pointingHand: .link
        case .iBeam: .horizontalText
        case .openHand: .grabIdle
        case .closedHand: .grabActive
        case .columnResize: .columnResize
        }
    }

    fileprivate var nsCursor: NSCursor {
        switch self {
        case .pointingHand: .pointingHand
        case .iBeam: .iBeam
        case .openHand: .openHand
        case .closedHand: .closedHand
        case .columnResize: .resizeLeftRight
        }
    }
}

/// macOS 15 起用 SwiftUI 的 `pointerStyle` (宿主视图自己管光标，AppKit 的光标区域会被它盖掉)；
/// macOS 14 退回悬停时 push、离开 / 消失 / 变不可用时 pop，保证成对，不会卡在手型上。
private struct HoverCursorModifier: ViewModifier {
    let cursor: HoverCursor
    let isActive: Bool

    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(isActive ? cursor.pointerStyle : nil)
        } else {
            content
                .onHover { setPushed($0 && isActive) }
                .onChange(of: isActive) { if !isActive { setPushed(false) } }
                .onDisappear { setPushed(false) }
        }
    }

    private func setPushed(_ wanted: Bool) {
        guard wanted != pushed else { return }
        if wanted { cursor.nsCursor.push() } else { NSCursor.pop() }
        pushed = wanted
    }
}

private struct HoverFeedback: ViewModifier {
    let cornerRadius: CGFloat
    let isEnabled: Bool
    let showsPress: Bool

    @State private var isHovered = false
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        let state = InteractionState(isHovered: isEnabled && isHovered, isPressed: isEnabled && isPressed, isEnabled: isEnabled)
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(state.overlay)
                    .allowsHitTesting(false)
            }
            .onHover { isHovered = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0).updating($isPressed) { _, pressed, _ in pressed = true },
                including: isEnabled && showsPress ? .all : .subviews
            )
            .pointingHandCursor(isEnabled)
    }
}
