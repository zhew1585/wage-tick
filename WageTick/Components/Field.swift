import SwiftUI

/// 设计稿 Field：上方标签 (12/500，muted)，下方白底输入框 (高 38、圆角 8、line 描边、左右内边距 12)，右侧可带单位 (13，muted)。
/// 引导 760 版的两种加大尺寸，标签都是 13/500、圆角 10：
/// - `.large` (月薪)：高 58、左右内边距 16、ink 1.5 描边、数字 24/600、单位 14。
/// - `.medium` (时间)：高 46、左右内边距 14、常规描边；里面的 `TimeInput` 自己传大一号的字体与箭头。
/// 输入框获得焦点时描边换成 accent，悬停 (未聚焦) 时非 `.large` 框描边换成 `strokeHover`；
/// 文本框的 I 型光标由系统给，`TimeInput` 自己挂手型。
///
/// 用法：
/// - 数字：`Field("月薪", text: $salaryText, suffix: "元")`，回车提交在外面挂 `.onSubmit(save)`
/// - 文字：`Field("名称", text: $name, prompt: "如 Switch 2", value: .text)`
/// - 其他输入控件：`Field("上班") { TimeInput(selection: $start) }`
struct Field<Content: View>: View {
    enum Size {
        case regular, medium, large

        fileprivate var height: CGFloat {
            switch self {
            case .regular: 38
            case .medium: 46
            case .large: 58
            }
        }

        fileprivate var strokeWidth: CGFloat {
            switch self {
            case .regular, .medium: 1
            case .large: 1.5
            }
        }

        fileprivate var radius: CGFloat {
            switch self {
            case .regular: Radius.control
            case .medium, .large: Radius.r10
            }
        }

        fileprivate var padding: CGFloat {
            switch self {
            case .regular: Spacing.s12
            case .medium: Spacing.s14
            case .large: Spacing.s16
            }
        }

        fileprivate var labelFont: Font {
            switch self {
            case .regular: AppFont.label
            case .medium, .large: AppFont.bodyMedium
            }
        }

        fileprivate var suffixFont: Font {
            switch self {
            case .regular, .medium: AppFont.body
            case .large: AppFont.lead
            }
        }
    }

    let label: String?
    var size: Size = .regular
    var suffix: String?
    @ViewBuilder let content: () -> Content

    @FocusState private var focused: Bool
    @State private var hovering = false

    init(_ label: String?, size: Size = .regular, suffix: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.size = size
        self.suffix = suffix
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            if let label {
                Text(label).font(size.labelFont).foregroundStyle(Palette.muted)
            }
            box
        }
    }

    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: size.radius)
        return HStack(spacing: Spacing.s8) {
            content()
                .focused($focused)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let suffix {
                Text(suffix).font(size.suffixFont).foregroundStyle(Palette.muted)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, size.padding)
        .frame(height: size.height)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(stroke, lineWidth: size.strokeWidth))
        .onHover { hovering = $0 }
    }

    private var stroke: Color {
        if focused { return Palette.accent }
        if size == .large { return Palette.ink }
        return hovering ? Palette.strokeHover : Palette.line
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
        case (.number, .medium): AppFont.numFieldMedium
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
