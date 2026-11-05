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
struct ThemeSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ThemeSwitchRow(configuration: configuration)
    }
}

extension ToggleStyle where Self == ThemeSwitchToggleStyle {
    static var themeSwitch: ThemeSwitchToggleStyle { ThemeSwitchToggleStyle() }
}

/// 单独成视图才能读到 `isEnabled`：不可用时变淡、不响应点击。
private struct ThemeSwitchRow: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled

    private static let trackSize = CGSize(width: 34, height: 20)
    private static let knobSize: CGFloat = 16
    private static let inset: CGFloat = 2
    private static let disabledOpacity = 0.4

    var body: some View {
        HStack {
            configuration.label
                .font(AppFont.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Spacing.s8)
            track
        }
        .padding(.vertical, Spacing.s10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else { return }
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        }
        .opacity(isEnabled ? 1 : Self.disabledOpacity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "开" : "关")
    }

    private var track: some View {
        Capsule()
            .fill(configuration.isOn ? Palette.money : Palette.line)
            .frame(width: Self.trackSize.width, height: Self.trackSize.height)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(Palette.card)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .padding(Self.inset)
            }
    }
}
