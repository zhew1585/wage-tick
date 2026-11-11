import SwiftUI
import WageCore

/// 发薪日表单「碰上不上班的日子」的三段小切换 (issue #20，设计稿 QgdwY)：撑满宽度，第一段按文字宽，其余两段平分剩下的。
/// 样子同 `PayBasisSwitch`：surface 底，选中的白底、12/600 ink 加细阴影，没选中的 12/400 muted。
///
/// 用法：`PaydayShiftSwitch(selection: shift) { shift = $0 }`
struct PaydayShiftSwitch: View {
    let selection: PaydayShift
    let select: (PaydayShift) -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(Array(PaydayShift.allCases.enumerated()), id: \.element) { index, shift in
                segment(shift)
                    .frame(maxWidth: index == 0 ? nil : .infinity)
                    .fixedSize(horizontal: index == 0, vertical: false)
            }
        }
        .padding(Spacing.s2)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r7))
    }

    private func segment(_ shift: PaydayShift) -> some View {
        let selected = shift == selection
        return Button { select(shift) } label: {
            Text(shift.label)
                .font(AppFont.ui(12, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.ink : Palette.muted)
                .lineLimit(1)
                .padding(.horizontal, Spacing.s10)
                .padding(.vertical, Spacing.s4)
                .frame(maxWidth: .infinity)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Radius.r5)
                            .fill(Palette.card)
                            .shadow(color: Palette.shadow, radius: 1, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
