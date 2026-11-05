import AppKit
import SwiftUI
import WageCore

/// 第 1 步 · 月薪 (设计稿 P1 引导 · 1 月薪)：大小牛、标题、月薪大号输入框、按试算结果给出的上班日与日薪提示。
struct OnboardingSalaryStep: View {
    private static let mascotSize: CGFloat = 72

    @Binding var salaryText: String
    let preview: OnboardingPreview?
    let errorMessage: String?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(.cowMascot)
                .resizable()
                .frame(width: Self.mascotSize, height: Self.mascotSize)
                .padding(.top, Spacing.s24)
                .padding(.horizontal, OnboardingLayout.side)
            OnboardingIntro(title: "嗨，牛马。\n一个月赚多少？", subtitle: "税前还是到手，你说了算。只存在这台电脑上，谁也看不到。")
            OnboardingBody(errorMessage: errorMessage) {
                Field("月薪", text: $salaryText, suffix: "元", size: .large)
                    .onSubmit(onSubmit)
                if let hint = preview?.salaryHint {
                    OnboardingHint(icon: .OnboardingIcon.calculator, text: hint)
                }
            }
        }
    }
}

/// 第 2 步 · 作息 (设计稿 P1 引导 · 2 作息)：上下班一行两格，灰底分组里是午休开关与午休时段。
/// 字段名照设计稿 (「上班」「有午休」)，与设置页共用的 `ScheduleFields` 不同，所以单独排。
struct OnboardingScheduleStep: View {
    @Binding var draft: ScheduleDraft
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingIntro(title: "几点上班，几点下班？", subtitle: "按计划时间算钱，不打卡。午休时段数字会暂停。")
            OnboardingBody(errorMessage: errorMessage) {
                timeRow("上班", $draft.start, "下班", $draft.end)
                VStack(alignment: .leading, spacing: Spacing.s10) {
                    ToggleRow("有午休", isOn: $draft.lunchEnabled)
                    if draft.lunchEnabled {
                        timeRow("午休开始", $draft.lunchStart, "午休结束", $draft.lunchEnd)
                    }
                }
                .padding(.top, Spacing.s4)
                .padding(.bottom, draft.lunchEnabled ? Spacing.s14 : Spacing.s4)
                .padding(.horizontal, Spacing.s14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: OnboardingLayout.groupRadius))
            }
        }
    }

    private func timeRow(_ startLabel: String, _ start: Binding<Date>, _ endLabel: String, _ end: Binding<Date>) -> some View {
        HStack(spacing: Spacing.s10) {
            Field(startLabel, suffix: "▾") { TimeInput(selection: start) }
            Field(endLabel, suffix: "▾") { TimeInput(selection: end) }
        }
    }
}

/// 第 3 步 · 开机自启 (设计稿 P1 引导 · 3 完成)：开机自启开关，下面是按已填内容试算出的菜单栏预览。
struct OnboardingLaunchStep: View {
    @Binding var launchAtLogin: Bool
    let preview: OnboardingPreview?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingIntro(title: "最后一步", subtitle: "让小牛每天开机就上岗。")
            OnboardingBody(errorMessage: errorMessage) {
                ToggleRow("开机自动启动", isOn: $launchAtLogin)
                    .padding(.vertical, Spacing.s4)
                    .padding(.horizontal, Spacing.s14)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: OnboardingLayout.groupRadius))
                if let preview {
                    previewBox(preview)
                }
            }
        }
    }

    private func previewBox(_ preview: OnboardingPreview) -> some View {
        let shape = RoundedRectangle(cornerRadius: OnboardingLayout.groupRadius)
        return VStack(alignment: .leading, spacing: Spacing.s10) {
            Text("设置好之后，菜单栏会是这样").font(AppFont.caption).foregroundStyle(Palette.muted)
            MenuBarMock(display: preview.menuBar)
            if let note = preview.carryOverNote {
                Text(note)
                    .font(AppFont.caption)
                    .lineSpacing(max(0, OnboardingIntro.lineGap(fontSize: 12)))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(shape.strokeBorder(Palette.line))
    }
}

/// 设计稿 Intro：标题 22/700 行高 1.3 (`title` 里用 \n 分行)，副标题 13 muted 行高 1.5，间隔 8；上 20、左右 24。
struct OnboardingIntro: View {
    let title: String
    let subtitle: String

    /// 设计稿行高是字号的倍数，SwiftUI 只能设行间距：目标行高减去字体自带的行高 (Noto Sans SC 约 1.45 倍)。
    /// 结果可能为负 (标题 1.3 倍比字体自带的矮)，`lineSpacing` 不认负数，标题因此按行拆开、用负的行距叠。
    static func lineGap(fontSize: CGFloat, weight: AppFont.Weight = .regular, lineHeight: CGFloat = 1.5) -> CGFloat {
        let natural = NSLayoutManager().defaultLineHeight(for: AppFont.nsFont(.ui, size: fontSize, weight: weight))
        return fontSize * lineHeight - natural
    }

    /// 与 `AppFont.title`、`AppFont.body` 的字号一致。
    private static let titleSize: CGFloat = 22
    private static let subtitleSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            VStack(alignment: .leading, spacing: Self.lineGap(fontSize: Self.titleSize, weight: .bold, lineHeight: 1.3)) {
                ForEach(title.split(separator: "\n").map(String.init), id: \.self) { line in
                    Text(line).font(AppFont.title)
                }
            }
            .foregroundStyle(Palette.ink)
            Text(subtitle)
                .font(AppFont.body)
                .lineSpacing(max(0, Self.lineGap(fontSize: Self.subtitleSize)))
                .foregroundStyle(Palette.muted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Spacing.s20)
        .padding(.horizontal, OnboardingLayout.side)
    }
}

/// 设计稿 Body：上下 22、左右 24，各块间隔 14；最后是校验失败的提示。
struct OnboardingBody<Content: View>: View {
    let errorMessage: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s14) {
            content()
            if let errorMessage {
                Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
        }
        .padding(.vertical, OnboardingLayout.bottom)
        .padding(.horizontal, OnboardingLayout.side)
    }
}

/// 输入框下方的一行提示：13pt 图标 + 12 号 muted 文字，间隔 6。
struct OnboardingHint: View {
    let icon: ImageResource
    let text: String

    var body: some View {
        HStack(spacing: Spacing.s6) {
            PhosphorIcon(icon, size: 13)
            Text(text).font(AppFont.caption)
        }
        .foregroundStyle(Palette.muted)
    }
}

/// 资源目录里的 Phosphor 模板图 (如 `.OnboardingIcon.calculator`)，颜色跟随 `foregroundStyle`。
struct PhosphorIcon: View {
    let resource: ImageResource
    var size: CGFloat = 14

    init(_ resource: ImageResource, size: CGFloat = 14) {
        self.resource = resource
        self.size = size
    }

    var body: some View {
        Image(resource)
            .renderingMode(.template)
            .resizable()
            .frame(width: size, height: size)
    }
}
