import SwiftUI

/// 时刻选择 (时:分)，放进 `Field` 里用：`Field("上班") { TimeInput(selection: $start) }`。
/// 外观照设计稿 P1 引导 · 2 作息：输入框里是 JetBrains Mono 14 的「09:00」，右侧一个向下箭头，不能手填。
/// 点开弹出 `TimePickerPopover`：左列小时 00-23、右列分钟 00-59。选小时后留在弹层里，选分钟后收起。
struct TimeInput: View {
    @Binding var selection: Date
    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: Spacing.s8) {
                Text(TimeOfDay(selection).text)
                    .font(AppFont.numField)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                PhosphorIcon(.caretDown, size: 12)
                    .foregroundStyle(isOpen ? Palette.accent : Palette.muted)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(TimeOfDay(selection).text)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            TimePickerPopover(selection: $selection) { isOpen = false }
        }
    }
}

/// 弹出的时间选择：两列可滚动列表，打开时自动滚到当前值。
/// 选中项 accent-soft 底、accent 字；悬停项 surface 底；其余 ink 字。
struct TimePickerPopover: View {
    @Binding var selection: Date
    let dismiss: () -> Void

    private static let hours = Array(0..<24)
    private static let minutes = Array(0..<60)

    var body: some View {
        let time = TimeOfDay(selection)
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack(spacing: 0) {
                columnTitle("时")
                columnTitle("分")
            }
            HStack(spacing: Spacing.s6) {
                TimeColumn(values: Self.hours, selected: time.hour) { hour in
                    selection = time.with(hour: hour).date
                }
                Rectangle().fill(Palette.line).frame(width: 1)
                TimeColumn(values: Self.minutes, selected: time.minute) { minute in
                    selection = time.with(minute: minute).date
                    dismiss()
                }
            }
            .frame(height: 216)
        }
        .padding(Spacing.s10)
        .frame(width: 168)
        .background(Palette.bg)
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(AppFont.label)
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity)
    }
}

/// 一列数字 (小时或分钟)，两位补零。
private struct TimeColumn: View {
    let values: [Int]
    let selected: Int
    let pick: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Spacing.s2) {
                    ForEach(values, id: \.self) { value in
                        TimeCell(value: value, isSelected: value == selected) { pick(value) }
                            .id(value)
                    }
                }
            }
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TimeCell: View {
    let value: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(String(format: "%02d", value))
                .font(AppFont.num(13, isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Palette.accent : Palette.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(background, in: RoundedRectangle(cornerRadius: Radius.r6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected { return Palette.accentSoft }
        return isHovered ? Palette.surface : .clear
    }
}

/// `Date` 里的时与分；改时或分时保留另一项，秒归零。
private struct TimeOfDay {
    let hour: Int
    let minute: Int
    private let base: Date

    init(_ date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? 0
        minute = parts.minute ?? 0
        base = date
    }

    private init(hour: Int, minute: Int, base: Date) {
        self.hour = hour
        self.minute = minute
        self.base = base
    }

    var text: String { String(format: "%02d:%02d", hour, minute) }

    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    func with(hour: Int) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute, base: base) }
    func with(minute: Int) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute, base: base) }
}
