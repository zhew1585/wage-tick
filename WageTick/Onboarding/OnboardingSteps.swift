import SwiftUI
import WageCore

/// 第 1 步 · 工资的头图 (大胆版设计稿「引导-1工资」)：标题「嗨，牛马。一个月赚多少？」(按天时「一天赚多少？」)，
/// 头图里就是大号工资输入，下面一行「只存在这台电脑上，谁也看不到」，打哈欠的小牛说「我先替你保密」。
struct OnboardingSalaryHero: View {
    @Binding var salaryText: String
    let payBasis: PayBasis
    let collapse: CGFloat
    let onSubmit: () -> Void

    var body: some View {
        BoldHero(
            theme: .orange,
            kicker: payBasis == .daily ? "嗨，牛马。一天赚多少？" : "嗨，牛马。一个月赚多少？",
            caption: "只存在这台电脑上，谁也看不到",
            captionIcon: .lockSimple,
            cow: .pose(.yawning),
            bubble: HeroBubbleContent(value: "我先替你保密", numeric: false),
            // 设计稿位置：说明行下方、离小牛约 20pt，不压到左上的五位数大号输入。
            bubbleOffset: CGSize(width: -152, height: 129),
            collapse: collapse,
            compactValue: salaryText.isEmpty ? nil : "¥\(salaryText)"
        ) {
            HeroSalaryInput(text: $salaryText, theme: .orange, onSubmit: onSubmit)
        }
    }
}

/// 第 1 步 · 工资的正文：「按月薪 | 按日薪」切换，下面「怎么休」四个大块选休息模式 (默认双休)，最后是校验提示。
struct OnboardingSalaryStep: View {
    @Binding var payBasis: PayBasis
    @Binding var restMode: RestModeChoice

    var body: some View {
        OnboardingBody {
            PayBasisPills(selection: payBasis) { payBasis = $0 }
            VStack(alignment: .leading, spacing: Spacing.s10) {
                Text("怎么休").font(AppFont.ui(13, .bold)).foregroundStyle(Palette.ink)
                RestModeTiles(selection: restMode) { restMode = $0 }
            }
        }
    }
}

/// 第 2 步 · 作息的头图 (大胆版设计稿「引导-2作息」)：标题「几点上班，几点下班？」，大数字是标准工时 + 「小时一天」，
/// 下面一行「按计划算钱，不用打卡」，干饭的小牛说「饭点不算钱哦」。标准工时来自核心的试算快照，作息不合法时为「—」。
struct OnboardingScheduleHero: View {
    let rates: WageRates?
    let collapse: CGFloat

    var body: some View {
        // 作息算不出来 (如上下班同一时刻) 时写 0。
        let hours = rates?.standardHoursNumber ?? "0"
        BoldHero(
            theme: .orange,
            kicker: "几点上班，几点下班？",
            caption: "按计划算钱，不用打卡",
            captionIcon: .alarm,
            cow: .pose(.eating),
            bubble: HeroBubbleContent(value: "饭点不算钱哦", numeric: false),
            collapse: collapse,
            compactValue: hours
        ) {
            HeroAmount(text: hours, theme: .orange, unit: "小时一天")
        }
    }
}

/// 第 2 步 · 作息的正文：上班、下班两个粗描边时间框；饭点开关，打开后开饭、吃完两个时间框；
/// 浅底汇总条 (满勤日薪、时薪、本月上班日)，最后是校验提示。
struct OnboardingScheduleStep: View {
    @Binding var draft: ScheduleDraft
    let rates: WageRates?

    var body: some View {
        OnboardingBody {
            HStack(spacing: Spacing.s8) {
                BoldTimeBox(label: "上班", selection: $draft.start)
                BoldTimeBox(label: "下班", selection: $draft.end)
            }
            Toggle(isOn: $draft.lunchEnabled) {
                Text("饭点").font(AppFont.ui(13, .bold)).foregroundStyle(Palette.ink)
            }
            .toggleStyle(.ink(verticalPadding: 0))
            if draft.lunchEnabled {
                HStack(spacing: Spacing.s8) {
                    BoldTimeBox(label: "开饭", selection: $draft.lunchStart)
                    BoldTimeBox(label: "吃完", selection: $draft.lunchEnd)
                }
            }
            if let rates {
                OnboardingRatesBar(rates: rates)
            }
        }
    }
}

/// 头图下面的正文：上 20、左右 20、块间隔 16。校验失败的提示改成弹窗 (见 `OnboardingView`)。
struct OnboardingBody<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            content()
        }
        .padding(EdgeInsets(top: Spacing.s20, leading: Spacing.screen, bottom: Spacing.s16, trailing: Spacing.screen))
    }
}
