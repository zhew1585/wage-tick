import SwiftUI

/// 设计稿 Field：上方标签 (12/500，muted)，下方白底输入框 (高 38、圆角 8、line 描边、左右内边距 12)，右侧可带单位 (13，muted)。
/// 大号 (`.large`，引导页月薪)：高 46、ink 1.5 描边、数字 18/600。输入框获得焦点时描边换成 accent。
///
/// 用法：
/// - 数字：`Field("月薪", text: $salaryText, suffix: "元")`，回车提交在外面挂 `.onSubmit(save)`
/// - 文字：`Field("名称", text: $name, prompt: "如 Switch 2", value: .text)`
/// - 其他输入控件：`Field("上班") { TimeInput(selection: $start) }`
struct Field<Content: View>: View {
    enum Size {
        case regular, large

        fileprivate var height: CGFloat { self == .large ? 46 : 38 }
        fileprivate var strokeWidth: CGFloat { self == .large ? 1.5 : 1 }
    }

    let label: String?
    var size: Size = .regular
    var suffix: String?
    @ViewBuilder let content: () -> Content

    @FocusState private var focused: Bool

    init(_ label: String?, size: Size = .regular, suffix: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.size = size
        self.suffix = suffix
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            if let label {
                Text(label).font(AppFont.label).foregroundStyle(Palette.muted)
            }
            box
        }
    }

    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        return HStack(spacing: Spacing.s8) {
            content()
                .focused($focused)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let suffix {
                Text(suffix).font(AppFont.body).foregroundStyle(Palette.muted)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Spacing.s12)
        .frame(height: size.height)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(stroke, lineWidth: size.strokeWidth))
    }

    private var stroke: Color {
        if focused { return Palette.accent }
        return size == .large ? Palette.ink : Palette.line
    }
}

/// 输入框里放的是数字还是文字：数字用 JetBrains Mono，文字用 Noto Sans SC。
enum FieldValue {
    case number, text
}

extension Field where Content == FieldTextInput {
    init(
        _ label: String?, text: Binding<String>, prompt: String? = nil, suffix: String? = nil,
        value: FieldValue = .number, size: Size = .regular
    ) {
        self.init(label, size: size, suffix: suffix) {
            FieldTextInput(title: label ?? prompt ?? "", text: text, prompt: prompt, font: Self.font(value, size))
        }
    }

    private static func font(_ value: FieldValue, _ size: Size) -> Font {
        switch (value, size) {
        case (.number, .regular): AppFont.numField
        case (.number, .large): AppFont.numFieldLarge
        case (.text, _): AppFont.fieldText
        }
    }
}

/// `Field` 里的无边框文本输入。占位文字用 muted。
struct FieldTextInput: View {
    let title: String
    @Binding var text: String
    let prompt: String?
    let font: Font

    var body: some View {
        TextField(title, text: $text, prompt: prompt.map { Text($0).foregroundStyle(Palette.muted) })
            .textFieldStyle(.plain)
            .font(font)
    }
}
