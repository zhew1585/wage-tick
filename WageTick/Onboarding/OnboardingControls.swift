import AppKit
import SwiftUI
import WageCore

/// 引导第 1 步头图里的大号工资输入 (大胆版设计稿「引导-1工资」)：小号 ¥ + Archivo Black 白色大字，空着时显示半透明的「0」。
/// 位数多了字号自动缩小，整行不超过 `maxWidth` (给右下角小牛留位置)。
struct HeroSalaryInput: View {
    @Binding var text: String
    let theme: HeroTheme
    let onSubmit: () -> Void

    private static let size: CGFloat = 96
    private static let minSize: CGFloat = 40
    private static let maxWidth: CGFloat = 205

    var body: some View {
        let size = fittedSize
        HStack(alignment: .lastTextBaseline, spacing: Spacing.s2) {
            Text("¥").font(AppFont.heavy(Self.size * 0.34)).foregroundStyle(theme.kicker)
            // 占位「0」自己画：`prompt` 的颜色在 macOS 上会被系统占位色盖掉，橙底上看着发黑。
            TextField("工资", text: $text, prompt: Text(""))
                .textFieldStyle(.plain)
                .font(AppFont.heavy(size))
                .foregroundStyle(theme.number)
                .onSubmit(onSubmit)
                .background(alignment: .leading) {
                    if text.isEmpty {
                        Text("0").font(AppFont.heavy(size)).foregroundStyle(theme.number.opacity(0.45)).allowsHitTesting(false)
                    }
                }
        }
        .frame(maxWidth: Self.maxWidth + Self.size * 0.34, alignment: .leading)
        .accessibilityLabel("工资")
    }

    /// 按当前文字的实际宽度缩小字号，至少 `minSize`。
    private var fittedSize: CGFloat {
        let sample = text.isEmpty ? "0" : text
        let width = (sample as NSString).size(withAttributes: [.font: AppFont.nsFont(.heavy, size: Self.size)]).width
        guard width > Self.maxWidth else { return Self.size }
        return max(Self.minSize, (Self.size * Self.maxWidth / width).rounded(.down))
    }
}

/// 「按月薪 | 按日薪」大胆版切换：浅底胶囊轨道，选中的墨底白字。
struct PayBasisPills: View {
    let selection: PayBasis
    let select: (PayBasis) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PayBasis.allCases, id: \.self) { basis in
                let selected = basis == selection
                Button { select(basis) } label: {
                    Text("按\(basis.label)")
                        .font(AppFont.ui(14, selected ? .bold : .regular))
                        .foregroundStyle(selected ? Color.white : Palette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(InteractiveButtonStyle { label, state in
                    label
                        .background(selected ? Palette.ink : state.overlay, in: Capsule())
                        .contentShape(Capsule())
                })
                .disabled(selected)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Spacing.s4)
        .background(Palette.surface, in: Capsule())
    }
}

/// 「怎么休」四个大块 (两列)：标题 15/700、小字 12；选中的黄底粗描边，其余细描边。
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
        let shape = RoundedRectangle(cornerRadius: Radius.r14)
        return Button { select(choice) } label: {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(choice.title).font(AppFont.ui(15, .bold)).foregroundStyle(Palette.ink)
                Text(choice.subtitle).font(AppFont.ui(12)).foregroundStyle(selected ? Palette.ink : Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s14)
            .frame(height: 62)
        }
        .buttonStyle(InteractiveButtonStyle { label, state in
            label
                .background(selected ? Palette.highlight : Palette.bg, in: shape)
                .overlay(shape.fill(selected ? .clear : state.overlay))
                .overlay(shape.strokeBorder(Palette.ink, lineWidth: selected ? 2 : 1))
                .contentShape(shape)
        })
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 粗描边的时间框 (引导第 2 步)：上面一行小标签，框里居中 Archivo Black 的「10:00」，点开弹出时间选择 (`TimePickerPopover`)。
struct BoldTimeBox: View {
    let label: String
    @Binding var selection: Date

    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(label).font(AppFont.ui(12)).foregroundStyle(Palette.muted)
            Button { isOpen.toggle() } label: {
                Text(TimeOfDay(pickerDate: selection).clockText)
                    .font(AppFont.heavy(20))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(InteractiveButtonStyle { label, state in
                let shape = RoundedRectangle(cornerRadius: Radius.r14)
                return label
                    .background(Palette.bg, in: shape)
                    .overlay(shape.fill(state.overlay))
                    .overlay(shape.strokeBorder(isOpen ? Palette.accent : Palette.ink, lineWidth: 2))
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

/// 按这个作息算的汇总条 (浅底圆角)：满勤日薪、时薪、本月上班日三项，数字全部来自核心的试算快照 (`WageRates`)。
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
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r16))
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Palette.line.frame(width: 1, height: 30)
    }

    private func cell(_ item: StatItem) -> some View {
        VStack(spacing: Spacing.s2) {
            Text(item.value).font(AppFont.heavy(15)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(item.title).font(AppFont.ui(11)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 头图标题栏那一行的步骤胶囊「1 / 2」，与返回胶囊同位置同样子，只是不能点。
struct HeroStepChip: View {
    let text: String
    let theme: HeroTheme

    var body: some View {
        Text(text)
            .font(AppFont.ui(12, .bold))
            .foregroundStyle(theme.onChip)
            .padding(EdgeInsets(top: 3, leading: Spacing.s10, bottom: 3, trailing: Spacing.s10))
            .background(theme.chip, in: Capsule())
            .padding(.leading, WindowChrome.Titlebar.standard.leadingInset - Spacing.s4)
            .frame(height: WindowChrome.Titlebar.standard.height)
            .accessibilityLabel("第 \(text) 步")
    }
}
