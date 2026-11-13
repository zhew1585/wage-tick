import SwiftUI

/// 大胆版开关 (设置、引导第 2 步的饭点)：开为高亮黄轨道配白色圆钮靠右，关为浅色轨道配白色圆钮靠左；点整行切换。
/// 整行是一个按钮：悬停手型，轨道悬停、按下时叠一层；不可用时变淡。标签默认 14 ink，要别的字体直接写在标签 `Text` 上。
///
/// 用法：`Toggle("桌面悬浮小牛", isOn: $on).toggleStyle(.ink)`；不要上下内边距时 `.toggleStyle(.ink(verticalPadding: 0))`。
struct InkToggleStyle: ToggleStyle {
    var verticalPadding = Spacing.s10

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            configuration.label
                .font(AppFont.ui(14))
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

/// 36×22 的胶囊轨道与 16 的白色圆钮 (带一点投影，黄底、浅底上都看得出)。
private struct InkSwitchTrack: View {
    let isOn: Bool
    let overlay: Color

    var body: some View {
        Capsule()
            .fill(isOn ? Palette.highlight : Palette.line)
            .overlay(Capsule().fill(overlay))
            .frame(width: 36, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Palette.card)
                    .frame(width: 16, height: 16)
                    .shadow(color: Palette.ink.opacity(0.2), radius: 1.5, y: 1)
                    .padding(3)
            }
    }
}
