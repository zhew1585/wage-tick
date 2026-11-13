import SwiftUI

/// 大胆版的提醒弹窗 (替代系统 `alert`)：盖在窗口上的半透明墨色遮罩，中间一张白色圆角卡片，文字用圆润的站酷快乐体，
/// 站酷体一句话和一个墨色胶囊「知道了」。回车或 Esc 关掉，点遮罩也关。
///
/// 用法：`.boldAlert($message)`；`message` 不为 nil 时弹出，关掉后置回 nil。
/// 弹出期间外面的回车键默认按钮 (如「下一步」) 要让开：`.keyboardShortcut(message == nil ? .defaultAction : nil)`。
struct BoldAlert: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
            VStack(spacing: Spacing.s16) {
                Text(message)
                    .font(AppFont.round(22))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("知道了", action: dismiss)
                    .buttonStyle(.pill(.ink))
                    .keyboardShortcut(.defaultAction)
                Button("", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .padding(EdgeInsets(top: Spacing.s24, leading: Spacing.s24, bottom: Spacing.s20, trailing: Spacing.s24))
            .frame(width: 280)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .transition(.opacity)
    }
}

extension View {
    /// 盖一层大胆版提醒弹窗 (`BoldAlert`)：`message` 不为 nil 时弹出，关掉后置回 nil。
    func boldAlert(_ message: Binding<String?>) -> some View {
        overlay {
            if let text = message.wrappedValue {
                BoldAlert(message: text) { message.wrappedValue = nil }
            }
        }
        .animation(.easeOut(duration: 0.15), value: message.wrappedValue)
    }
}

/// 大胆版的二次确认弹窗 (替代系统确认 `alert`)：同 `BoldAlert` 的遮罩与白卡片，站酷快乐体标题、一段说明，
/// 下面左「取消」描边、右确认按钮 (危险操作红色实心)。Esc、点遮罩等同取消；回车不触发，免得误按清空。
struct BoldConfirm: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: cancel)
            VStack(spacing: Spacing.s12) {
                Text(title)
                    .font(AppFont.round(22))
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.s10) {
                    Button("取消", action: cancel)
                        .buttonStyle(.pill(.outline))
                        .keyboardShortcut(.cancelAction)
                    Button(confirmTitle, action: confirm)
                        .buttonStyle(.pill(.danger))
                }
                .padding(.top, Spacing.s8)
            }
            .padding(EdgeInsets(top: Spacing.s24, leading: Spacing.s20, bottom: Spacing.s20, trailing: Spacing.s20))
            .frame(width: 300)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .transition(.opacity)
    }
}

extension View {
    /// 盖一层大胆版二次确认弹窗 (`BoldConfirm`)：`isPresented` 为 true 时弹出，取消或确认后置回 false。
    func boldConfirm(
        _ title: String, isPresented: Binding<Bool>, message: String, confirmTitle: String, confirm: @escaping () -> Void
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                BoldConfirm(
                    title: title, message: message, confirmTitle: confirmTitle,
                    confirm: { isPresented.wrappedValue = false; confirm() },
                    cancel: { isPresented.wrappedValue = false }
                )
            }
        }
        .animation(.easeOut(duration: 0.15), value: isPresented.wrappedValue)
    }
}
