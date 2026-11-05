import AppKit
import SwiftUI
import WageCore

/// 第 1 步 · 月薪 (设计稿 P1 引导 · 1 月薪 · 760)：大小牛、标题、月薪大号输入框。
/// 设计稿里小牛实例框是 104，但图形没跟着放大，画出来仍是 72 靠左上；这里照画出来的样子：72 的图占 104 的位置。
struct OnboardingSalaryStep: View {
    private static let mascotSize: CGFloat = 72
    private static let mascotSlot: CGFloat = 104

    @Binding var salaryText: String
    let errorMessage: String?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(.cowMascot)
                .resizable()
                .frame(width: Self.mascotSize, height: Self.mascotSize)
                .frame(width: Self.mascotSlot, height: Self.mascotSlot, alignment: .topLeading)
                .padding(.top, OnboardingStepsLayout.firstTop)
                .padding(.horizontal, OnboardingLayout.side)
            OnboardingIntro(
                title: "嗨，牛马。\n一个月赚多少？", subtitle: "税前还是到手，你说了算。只存在这台电脑上，谁也看不到。",
                top: OnboardingStepsLayout.introAfterMascot
            )
            OnboardingBody(spacing: Spacing.s16, errorMessage: errorMessage) {
                Field("月薪", text: $salaryText, suffix: "元", size: .large)
                    .onSubmit(onSubmit)
            }
        }
    }
}

/// 第 2 步 · 作息 (设计稿 P1 引导 · 2 作息 · 760)：上下班一行两格；午休开关，打开后午休时段一行两格；
/// 分隔线下是「按这个作息算」的工资换算卡片。
/// 字段名与尺寸照设计稿 (「上班」「午休」、加高输入框)，与设置页共用的 `ScheduleFields` 不同，所以单独排。
struct OnboardingScheduleStep: View {
    @Binding var draft: ScheduleDraft
    let rates: WageRates?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingIntro(
                title: "几点上班，几点下班？", subtitle: "按计划时间算钱，不打卡。午休时段数字会暂停。",
                top: OnboardingStepsLayout.firstTop
            )
            OnboardingBody(spacing: Spacing.s22, errorMessage: errorMessage) {
                timeRow("上班", $draft.start, "下班", $draft.end)
                VStack(alignment: .leading, spacing: Spacing.s12) {
                    Toggle(isOn: $draft.lunchEnabled) {
                        Text("午休").font(AppFont.bodyMedium).foregroundStyle(Palette.muted)
                    }
                    .toggleStyle(.themeSwitch(verticalPadding: 0))
                    if draft.lunchEnabled {
                        timeRow("午休开始", $draft.lunchStart, "午休结束", $draft.lunchEnd)
                    }
                }
                if let rates {
                    OnboardingRatesSection(rates: rates)
                }
            }
        }
    }

    private func timeRow(_ startLabel: String, _ start: Binding<Date>, _ endLabel: String, _ end: Binding<Date>) -> some View {
        HStack(spacing: Spacing.s12) {
            timeField(startLabel, start)
            timeField(endLabel, end)
        }
    }

    private func timeField(_ label: String, _ selection: Binding<Date>) -> some View {
        Field(label, size: .tall) {
            TimeInput(selection: selection, font: AppFont.numFieldTall, caretSize: OnboardingStepsLayout.caretSize)
        }
    }
}

/// 「按这个作息算」(设计稿 Summary)：上边一条分隔线、上 18，12 号 muted 小标题，下面 surface 底的 2×2 卡片。
/// 数字全部来自核心的试算快照 (`WageRates`)，这里只排版。
struct OnboardingRatesSection: View {
    let rates: WageRates

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            Text("按这个作息算").font(AppFont.caption).foregroundStyle(Palette.muted)
            VStack(spacing: 0) {
                row(rates.attendanceDays, rates.dailyWage)
                Rectangle().fill(Palette.line).frame(height: 1)
                row(rates.standardHours, rates.hourlyWage)
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r10))
        }
        .padding(.top, Spacing.s18)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// 一行两项，中间一条 34 高的竖线；两项等宽，右项左边再空 14。
    private func row(_ left: StatItem, _ right: StatItem) -> some View {
        HStack(spacing: 0) {
            cell(left).frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Palette.line).frame(width: 1, height: OnboardingStepsLayout.dividerHeight)
            cell(right).padding(.leading, Spacing.s14).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.s14)
        .padding(.horizontal, Spacing.s16)
    }

    private func cell(_ item: StatItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(item.title).font(AppFont.small).foregroundStyle(Palette.muted)
            Text(item.value).font(AppFont.numStat).foregroundStyle(Palette.ink)
        }
    }
}

/// 设计稿 Intro：标题 28/700 行高 1.3 (`title` 里用 \n 分行)，副标题 14 muted 行高 1.5，间隔 10；左右 24，上边距按步不同。
struct OnboardingIntro: View {
    let title: String
    let subtitle: String
    let top: CGFloat

    /// 设计稿行高是字号的倍数，SwiftUI 只能设行间距：目标行高减去字体自带的行高 (Noto Sans SC 约 1.45 倍)。
    /// 结果可能为负 (标题 1.3 倍比字体自带的矮)，`lineSpacing` 不认负数，标题因此按行拆开、用负的行距叠。
    static func lineGap(fontSize: CGFloat, weight: AppFont.Weight = .regular, lineHeight: CGFloat = 1.5) -> CGFloat {
        let natural = NSLayoutManager().defaultLineHeight(for: AppFont.nsFont(.ui, size: fontSize, weight: weight))
        return fontSize * lineHeight - natural
    }

    /// 与 `AppFont.display`、`AppFont.lead` 的字号一致。
    private static let titleSize: CGFloat = 28
    private static let subtitleSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s10) {
            VStack(alignment: .leading, spacing: Self.lineGap(fontSize: Self.titleSize, weight: .bold, lineHeight: 1.3)) {
                ForEach(title.split(separator: "\n").map(String.init), id: \.self) { line in
                    Text(line).font(AppFont.display)
                }
            }
            .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(AppFont.lead)
                .lineSpacing(max(0, Self.lineGap(fontSize: Self.subtitleSize)))
                .foregroundStyle(Palette.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, top)
        .padding(.horizontal, OnboardingLayout.side)
    }
}

/// 设计稿 Body：上 36、下 22、左右 24，块间隔按步不同；最后是校验失败的提示。
struct OnboardingBody<Content: View>: View {
    let spacing: CGFloat
    let errorMessage: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
            if let errorMessage {
                Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
        }
        .padding(.top, OnboardingStepsLayout.bodyTop)
        .padding(.bottom, OnboardingStepsLayout.bodyBottom)
        .padding(.horizontal, OnboardingLayout.side)
    }
}

/// 两步正文的排版尺寸 (设计稿 P1 引导 · 760)。
private enum OnboardingStepsLayout {
    /// 步骤条下面第一块 (第 1 步小牛、第 2 步标题) 的上边距。
    static let firstTop: CGFloat = 44
    /// 第 1 步标题离小牛。
    static let introAfterMascot: CGFloat = 28
    static let bodyTop: CGFloat = 36
    static let bodyBottom: CGFloat = 22
    /// 时间输入框里的向下箭头。
    static let caretSize: CGFloat = 14
    /// 工资换算卡片里两项之间的竖线高。
    static let dividerHeight: CGFloat = 34
}
