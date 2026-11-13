import SwiftUI
import WageCore

/// 面板底部入口栏 (PRD F4 第 8 条，设计稿「大胆风格」Footer)：bg 底、上边一条细线，历史、目标、设置靠左排开；
/// 右侧：今天请了假时是请假入口 (点一下修改)，否则设了发薪日时是距发薪 (issue #20，设计稿「发薪日倒计时 · 方案」E8IYR / pyihH)。
struct PanelFooter: View {
    /// 今天的请假：短描述与进入修改的动作。
    struct LeaveEntry {
        let text: String
        let edit: () -> Void
    }

    let payday: PaydayFooter?
    var leave: LeaveEntry?
    let openHistory: () -> Void
    let openGoals: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s2) {
            FooterItem(icon: .calendarBlank, title: "历史", action: openHistory)
            FooterItem(icon: .flagBanner, title: "目标", action: openGoals)
            FooterItem(icon: .gearSix, title: "设置", action: openSettings)
            Spacer()
            if let leave {
                LeaveIndicator(leave: leave)
            } else if let payday {
                PaydayIndicator(payday: payday)
            }
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.vertical, 5)
        .background(Palette.bg)
        .overlay(alignment: .top) { PanelDivider() }
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
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                PhosphorIcon(.coins, size: 13).iconOnTextBaseline(12)
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

/// 今天的请假：伞 + 短描述，muted；整条可点 (手型光标、悬停加底)，进入修改。悬停时文字变 ink、叠一层底。
private struct LeaveIndicator: View {
    let leave: PanelFooter.LeaveEntry

    var body: some View {
        Button(action: leave.edit) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
                PhosphorIcon(.umbrella, size: 13).iconOnTextBaseline(12)
                Text(leave.text).font(AppFont.caption).lineLimit(1).minimumScaleFactor(0.85)
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
        .help("修改今天的请假")
    }
}

/// 入口栏的一项：图标 14 + 文字 12，muted；悬停时文字变 ink、叠一层底，按下再深一档，手型光标。
private struct FooterItem: View {
    let icon: Phosphor
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                PhosphorIcon(icon, size: 14).iconOnTextBaseline(12)
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
