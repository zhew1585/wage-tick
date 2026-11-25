import AppKit
import SwiftUI
import WageCore

/// 引导第 1 步头图里的大号工资输入：¥ 26/600 + JetBrains Mono 54/700 墨色大字，光标用默认强调色，空着时显示淡色的「0」。
/// 最多五位整数 (到 9 万多)，字号固定：数字等宽，五位约 160 宽，输入过程中不缩放，也不压到右下角小牛。
struct HeroSalaryInput: View {
    @Binding var text: String
    let theme: HeroTheme
    let onSubmit: () -> Void
    @FocusState private var focused: Bool

    private static let size = HeroNumberInput.size
    /// 最多几位数字。
    static let maxDigits = 5

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.s2) {
            Text("¥").font(AppFont.num(HeroNumberInput.affixSize, .semibold)).foregroundStyle(Palette.ink)
            // 占位「0」自己画：`prompt` 的颜色在 macOS 上会被系统占位色盖掉。
            TextField("工资", text: $text, prompt: Text(""))
                .textFieldStyle(.plain)
                .font(AppFont.num(Self.size, .bold))
                .foregroundStyle(Palette.ink)
                .onSubmit(onSubmit)
                .focused($focused)
                .background(alignment: .leading) {
                    if text.isEmpty {
                        Text("0").font(AppFont.num(Self.size, .bold)).foregroundStyle(Palette.muted.opacity(0.45)).allowsHitTesting(false)
                    }
                }
                // 只留数字、最多五位：多打的字直接吞掉。
                .heroNumberLimit($text, maxDigits: Self.maxDigits)
        }
        .frame(width: 240, alignment: .leading)
        .padding(.top, HeroNumberInput.caretClearance)
        .accessibilityLabel("工资")
        // 打开就聚焦，可以直接输。
        .onAppear { focused = true }
    }
}

/// 「按月薪 | 按日薪」切换 (同经典 `ThemeSegmented`)：surface 底、圆角 9、内边距 3，选中段白底圆角 7 带淡投影、墨色 13/600，其余 muted 13。
struct PayBasisPills: View {
    let selection: PayBasis
    let select: (PayBasis) -> Void

    var body: some View {
        HStack(spacing: Spacing.s3) {
            ForEach(PayBasis.allCases, id: \.self) { basis in
                let selected = basis == selection
                let shape = RoundedRectangle(cornerRadius: Radius.r7)
                Button { select(basis) } label: {
                    Text("按\(basis.label)")
                        .font(AppFont.ui(13, selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(InteractiveButtonStyle { label, state in
                    label
                        .foregroundStyle(selected || state.isHovered ? Palette.ink : Palette.muted)
                        .background {
                            if selected {
                                shape.fill(Palette.card).shadow(color: Palette.shadow, radius: 1.5, y: 1)
                            } else {
                                shape.fill(state.overlay)
                            }
                        }
                        .contentShape(shape)
                })
                .disabled(selected)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Spacing.s3)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r9))
    }
}

/// 「怎么休」四个大块 (两列)：标题 14/600、小字 12 muted；未选中白底 line 描边，选中 accent-soft 底、accent 1.5 描边。
/// 顺序照设计稿：双休、单休、大小周 (这周休两天)、大小周 (这周休一天)。
struct RestModeTiles: View {
    let selection: RestModeChoice
    let select: (RestModeChoice) -> Void

    private static let order: [RestModeChoice] = [.twoDaysOff, .sundayOnly, .bigWeekNow, .smallWeekNow]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.s8), GridItem(.flexible())], spacing: Spacing.s8) {
            ForEach(Self.order, id: \.self, content: tile)
        }
    }

    private func tile(_ choice: RestModeChoice) -> some View {
        let selected = choice == selection
        let shape = RoundedRectangle(cornerRadius: Radius.r10)
        return Button { select(choice) } label: {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(choice.title).font(AppFont.section).foregroundStyle(selected ? Palette.accent : Palette.ink)
                Text(choice.subtitle).font(AppFont.caption).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s14)
            .frame(height: 62)
        }
        .buttonStyle(InteractiveButtonStyle { label, state in
            label
                .background(selected ? Palette.accentSoft : Palette.card, in: shape)
                .overlay(shape.fill(selected ? .clear : state.overlay))
                .overlay(shape.strokeBorder(selected ? Palette.accent : Palette.line, lineWidth: selected ? 1.5 : 1))
                .contentShape(shape)
        })
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 时间框 (引导第 2 步，同经典 Field 的中号框)：上面一行 12/500 muted 小标签，白底、圆角 10、line 描边 (打开时 accent)，
/// 框里居中 JetBrains Mono 17/600 的「10:00」，点开弹出时间选择 (`TimePickerPopover`)。
struct BoldTimeBox: View {
    let label: String
    @Binding var selection: Date

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(label).font(AppFont.label).foregroundStyle(Palette.muted)
            Button { isOpen.toggle() } label: {
                Text(TimeOfDay(pickerDate: selection).clockText)
                    .font(AppFont.numFieldMedium)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(InteractiveButtonStyle { label, state in
                let shape = RoundedRectangle(cornerRadius: Radius.r10)
                return label
                    .background(Palette.card, in: shape)
                    .overlay(shape.fill(state.overlay))
                    .overlay(shape.strokeBorder(isOpen ? Palette.accent : (state.isHovered ? Palette.strokeHover : Palette.line), lineWidth: isOpen ? 1.5 : 1))
                    .contentShape(shape)
            })
            .accessibilityLabel(label)
            .accessibilityValue(TimeOfDay(pickerDate: selection).clockText)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                TimePickerPopover(selection: $selection) { isOpen = false }
            }
        }
    }
}

/// 按这个作息算的汇总条 (surface 底、圆角 10)：满勤日薪、时薪、本月上班日三项，数值 JetBrains Mono 15/600、标题 11 muted，
/// 数字全部来自核心的试算快照 (`WageRates`)。
struct OnboardingRatesBar: View {
    let rates: WageRates

    var body: some View {
        HStack(spacing: 0) {
            cell(rates.dailyWage)
            divider
            cell(rates.hourlyWage)
            divider
            cell(rates.attendanceDays)
        }
        .padding(.vertical, Spacing.s14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r10))
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Palette.line.frame(width: 1, height: 30)
    }

    private func cell(_ item: StatItem) -> some View {
        VStack(spacing: Spacing.s2) {
            Text(item.value).font(AppFont.num(15, .semibold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(item.title).font(AppFont.ui(11)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 头图标题栏那一行的步骤「1 / 2」，与返回同位置：等宽 12/500 muted，无底，不能点。
struct HeroStepChip: View {
    let text: String
    let theme: HeroTheme

    var body: some View {
        Text(text)
            .font(AppFont.num(12, .medium))
            .foregroundStyle(theme.classic.secondary)
            .padding(.vertical, 3)
            .padding(.leading, WindowChrome.Titlebar.hero.leadingInset - Spacing.s4)
            .frame(height: WindowChrome.Titlebar.hero.height)
            .accessibilityLabel("第 \(text) 步")
    }
}
