import SwiftUI

/// 设置、引导第 2 步饭点的开关，经典版的样子 (同 `ThemeSwitchToggleStyle`)：34×20 的轨道，开为主题橙配白色圆钮靠右，关为浅色靠左；点整行切换。
/// 整行是一个按钮：悬停手型，轨道悬停、按下时叠一层；不可用时变淡。标签默认 13 ink，要别的字体直接写在标签 `Text` 上。
///
/// 用法：`Toggle("桌面悬浮小牛", isOn: $on).toggleStyle(.ink)`；不要上下内边距时 `.toggleStyle(.ink(verticalPadding: 0))`。
struct InkToggleStyle: ToggleStyle {
    var verticalPadding = Spacing.s10

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            configuration.label
                .font(AppFont.body)
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(InteractiveButtonStyle { label, state in
            HStack {
                label
                Spacer(minLength: Spacing.s8)
                InkSwitchTrack(isOn: configuration.isOn, overlay: state.overlay)
            }
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
            .opacity(state.isEnabled ? 1 : 0.4)
        })
        .accessibilityValue(configuration.isOn ? "开" : "关")
    }
}

extension ToggleStyle where Self == InkToggleStyle {
    static var ink: InkToggleStyle { InkToggleStyle() }

    static func ink(verticalPadding: CGFloat) -> InkToggleStyle {
        InkToggleStyle(verticalPadding: verticalPadding)
    }
}

/// 34×20 的胶囊轨道与 16 的白色圆钮：开 accent 橙，关 line 浅色。
private struct InkSwitchTrack: View {
    let isOn: Bool
    let overlay: Color

    var body: some View {
        Capsule()
            .fill(isOn ? Palette.accent : Palette.line)
            .overlay(Capsule().fill(overlay))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Palette.card)
                    .frame(width: 16, height: 16)
                    .padding(2)
            }
    }
}
