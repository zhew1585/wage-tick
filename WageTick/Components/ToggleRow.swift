import SwiftUI

/// 设计稿 Toggle Row：左边文字 (13，ink)，右边 34×20 胶囊开关，上下内边距 10，占满宽度。
/// 用法：`ToggleRow("开机自动启动", isOn: $launchAtLogin)`；
/// 只要开关外观时给任意 `Toggle` 挂 `.toggleStyle(.themeSwitch)`。
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.themeSwitch)
    }
}

/// 胶囊开关：开为 money 底、圆钮靠右，关为 line 底、圆钮靠左；点整行切换。
/// 整行是一个按钮：悬停手型，开关轨道悬停、按下时叠一层加深；不可用时变淡、没有反馈。
struct ThemeSwitchToggleStyle: ToggleStyle {
    private static let disabledOpacity = 0.4

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
                ThemeSwitchTrack(isOn: configuration.isOn, overlay: state.overlay)
            }
            .padding(.vertical, Spacing.s10)
            .contentShape(Rectangle())
            .opacity(state.isEnabled ? 1 : Self.disabledOpacity)
        })
        .accessibilityValue(configuration.isOn ? "开" : "关")
    }
}

extension ToggleStyle where Self == ThemeSwitchToggleStyle {
    static var themeSwitch: ThemeSwitchToggleStyle { ThemeSwitchToggleStyle() }
}

/// 34×20 的胶囊轨道与 16 的圆钮；`overlay` 是悬停、按下时叠在轨道上的一层。
private struct ThemeSwitchTrack: View {
    let isOn: Bool
    let overlay: Color

    private static let trackSize = CGSize(width: 34, height: 20)
    private static let knobSize: CGFloat = 16
    private static let inset: CGFloat = 2

    var body: some View {
        Capsule()
            .fill(isOn ? Palette.money : Palette.line)
            .overlay(Capsule().fill(overlay))
            .frame(width: Self.trackSize.width, height: Self.trackSize.height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Palette.card)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .padding(Self.inset)
            }
    }
}
