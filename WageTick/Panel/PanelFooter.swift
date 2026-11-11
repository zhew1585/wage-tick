import SwiftUI
import WageCore

/// 面板底部入口栏 (PRD F4 第 8 条，设计稿 P2 Footer)：surface 底，历史、目标、设置靠左排开；
/// 设了发薪日时右侧是距发薪 (issue #20，设计稿「发薪日倒计时 · 方案」E8IYR / pyihH)。
struct PanelFooter: View {
    let payday: PaydayFooter?
    let openHistory: () -> Void
    let openGoals: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            FooterItem(icon: .calendarBlank, title: "历史", action: openHistory)
            FooterItem(icon: .flagBanner, title: "目标", action: openGoals)
            FooterItem(icon: .gearSix, title: "设置", action: openSettings)
            Spacer()
            if let payday {
                PaydayIndicator(payday: payday)
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, Spacing.s10)
        .background(Palette.surface)
    }
}

/// 距发薪：52×4 的发薪周期进度条 (line 底、accent 填充) + 「距发薪 8 天」(11 muted 夹着 12/700 等宽 ink 天数)，
/// 前一天整句「明天发薪」(12/700 ink)；当天进度条满格变 money 绿，文字换成钱币图标 +「今天发薪」(12/700 money)。
/// 文字原样取自快照的 `PaydayFooter`。
private struct PaydayIndicator: View {
    let payday: PaydayFooter

    private static let barSize = CGSize(width: 52, height: 4)

    var body: some View {
        HStack(spacing: Spacing.s8) {
            cycleBar
            label
        }
        .padding(.horizontal, Spacing.s8)
    }

    private var cycleBar: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r2)
        return shape
            .fill(Palette.line)
            .overlay(alignment: .leading) {
                shape
                    .fill(payday.isPayday ? Palette.money : Palette.accent)
                    .frame(width: Self.barSize.width * min(max(payday.progress, 0), 1))
            }
            .frame(width: Self.barSize.width, height: Self.barSize.height)
    }

    @ViewBuilder
    private var label: some View {
        if payday.isPayday {
            HStack(spacing: Spacing.s3) {
                PhosphorIcon(.coins, size: 13)
                Text(payday.value).font(AppFont.ui(12, .bold))
            }
            .foregroundStyle(Palette.money)
        } else if let prefix = payday.prefix, let suffix = payday.suffix {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                Text(prefix).font(AppFont.small).foregroundStyle(Palette.muted)
                Text(payday.value).font(AppFont.num(12, .bold)).foregroundStyle(Palette.ink)
                Text(suffix).font(AppFont.small).foregroundStyle(Palette.muted)
            }
        } else {
            Text(payday.value).font(AppFont.ui(12, .bold)).foregroundStyle(Palette.ink)
        }
    }
}

/// 入口栏的一项：图标 14 + 文字 12，muted；悬停时文字变 ink、叠一层底，按下再深一档，手型光标。
private struct FooterItem: View {
    let icon: Phosphor
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                PhosphorIcon(icon, size: 14)
                Text(title).font(AppFont.caption)
            }
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s6)
        }
        .buttonStyle(InteractiveButtonStyle { label, state in
            label
                .foregroundStyle(state.isHovered || state.isPressed ? Palette.ink : Palette.muted)
                .background(state.overlay, in: RoundedRectangle(cornerRadius: Radius.r6))
                .contentShape(Rectangle())
        })
    }
}
