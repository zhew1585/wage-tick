import SwiftUI
import WageCore

/// 「月薪 | 日薪」小切换 (issue #16，设计稿「按天算工资」方案 A)：放在工资输入框上方，代替原来的「月薪」标签。
/// surface 底的小分段，选中的白底、12/600 ink 加细阴影，没选中的 12/400 muted。引导第 1 步、设置与历史的改工资表单共用。
///
/// 用法：`PayBasisSwitch(selection: basis) { basis = $0 }`，下面的输入框单位用 `basis.unit`。
struct PayBasisSwitch: View {
    let selection: PayBasis
    let select: (PayBasis) -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(PayBasis.allCases, id: \.self) { basis in
                let selected = basis == selection
                Button { select(basis) } label: {
                    Text(basis.label)
                        .font(AppFont.ui(12, selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Palette.ink : Palette.muted)
                        .padding(.horizontal, Spacing.s10)
                        .padding(.vertical, Spacing.s3)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: Radius.r5)
                                    .fill(Color.white)
                                    .shadow(color: Palette.ink.opacity(0.1), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.s2)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r7))
    }
}
