import AppKit
import SwiftUI
import WageCore

/// 引导里的试算提示：把已填内容当作完成引导试算一遍 (`AppModel.dryRun`，不保存)，只读快照里的结果，不自己算钱。
/// 月薪还没填对 (试算被校验拦下) 时为 nil，提示整块不显示。
struct OnboardingPreview {
    /// 第 1 步提示，如「11月有 21 个上班日，满勤日薪 ¥952.381」；本月没有要上班的日子时为 nil。
    let salaryHint: String?
    /// 第 3 步菜单栏预览：完成引导后此刻菜单栏的样子。
    let menuBar: MenuBarDisplay
    /// 第 3 步预览下的说明，如「本月已过的 3 个上班日按满勤计入，第一天本月累计就有 ¥2857.143。」；
    /// 本月还没有已过的上班日时为 nil。
    let carryOverNote: String?

    @MainActor
    init?(model: AppModel, input: OnboardingInput) {
        guard case .success(let snapshot) = model.dryRun(.completeOnboarding(input)), let today = snapshot.today else {
            return nil
        }
        menuBar = snapshot.menuBar
        // 本月上班日：月日历里不是休息日的天数 (试算时没有请假、扣钱，满勤与未到都算)。
        let workdays = snapshot.historyMonth(today.date.yearMonth)?.days.filter { $0.kind != .rest }.count ?? 0
        salaryHint = workdays > 0
            ? "\(today.date.month)月有 \(workdays) 个上班日，满勤日薪 \(Self.money(today.dailyWage))"
            : nil
        carryOverNote = today.attendedDays > 0
            ? "本月已过的 \(today.attendedDays) 个上班日按满勤计入，第一天本月累计就有 \(Self.money(today.monthToDate))。"
            : nil
    }

    /// 金额展示同核心的 D9 规则 (PRD 4.7.1 第 5 条)：四舍五入到 4 位、截掉末尾 0、带 ¥，如「¥952.381」。
    /// 核心的 `Format` 不对外，这两个数在快照里没有现成文字，只好在这里按同一规则格式化。
    private static func money(_ amount: Decimal) -> String {
        var input = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 4, .plain)
        return "¥" + NSDecimalNumber(decimal: rounded).stringValue
    }
}

/// 设计稿里示意的系统菜单栏：小牛 + 数字，旁边是 Wi-Fi、电池图标，靠右排。
/// 小牛用菜单栏同一张图 (`CowIcon`，含日状态角标)，数字取自试算快照，与真实菜单栏一致。
struct MenuBarMock: View {
    let display: MenuBarDisplay

    private static let height: CGFloat = 30
    private static let iconSize: CGFloat = 15

    var body: some View {
        HStack(spacing: Spacing.s12) {
            HStack(spacing: Spacing.s4) {
                Image(nsImage: CowIcon.image(for: display.pose)).renderingMode(.template)
                if let text = display.text {
                    Text(text).font(AppFont.numMenuBar)
                }
            }
            PhosphorIcon(.OnboardingIcon.wifiHigh, size: Self.iconSize)
            PhosphorIcon(.OnboardingIcon.batteryHigh, size: Self.iconSize)
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, Spacing.s10)
        .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .trailing)
        .background(Palette.menuBarMock, in: RoundedRectangle(cornerRadius: Radius.r6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("菜单栏预览 \(display.text ?? "")")
    }
}
