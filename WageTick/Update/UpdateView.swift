import SwiftUI
import WageCore

/// 更新窗口的内容 (经典视觉，屏次同大胆版设计稿「更新-1发现新版本」至「更新-4已是最新」)：顶上 210 高的米白头图
/// (17/700 标题、JetBrains Mono 大号版本号或百分比、一行说明，右下角小牛)，下面按屏放更新内容卡片、进度块、说明与按钮。
/// 各屏只换小牛姿势；出错沿用「已是最新」的样子。
struct UpdateView: View {
    let model: UpdateWindowController.Model
    let perform: (@escaping () -> Void) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let screen = model.screen {
                content(screen)
            }
        }
        .frame(width: WindowMetrics.size.width)
        .background(Palette.bg)
    }

    @ViewBuilder
    private func content(_ screen: UpdateScreen) -> some View {
        switch screen {
        case .found(let version, let current, let notes, let later, let download):
            UpdateHero(theme: .orange, kicker: "有新版本啦", number: version, caption: "你现在用的是 \(current)", pose: .excited)
            body {
                UpdateNotesCard(notes: notes)
                footnote("打开了自动更新的话，新版本会在后台自己下载")
                buttons(secondary: ("以后再说", later), primary: ("下载更新", download))
            }
        case .downloading(let version, let received, let expected, let cancel):
            let ratio = Self.ratio(received: received, expected: expected)
            UpdateHero(
                theme: .orange, kicker: "正在下载 \(version)", number: Self.percent(ratio),
                caption: expected > 0 ? "\(Self.megabytes(received)) / \(Self.megabytes(expected))" : Self.megabytes(received),
                pose: .working
            )
            body {
                UpdateProgressBlocks(ratio: ratio)
                footnote("下载完会先问你，不会突然重启")
                buttons(secondary: ("取消下载", cancel), primary: nil)
            }
        case .extracting(let version):
            UpdateHero(theme: .orange, kicker: "正在准备 \(version)", number: Self.percent(1), caption: "马上就好", pose: .working)
            body {
                UpdateProgressBlocks(ratio: 1)
            }
        case .ready(let version, let notes, let later, let restart):
            UpdateHero(theme: .mint, kicker: "新版本准备好了", number: version, caption: "已下载并校验完成，重启后生效", pose: .paid)
            body {
                UpdateNotesCard(notes: notes)
                footnote("选稍后的话，下次退出时自动装好；也可以在菜单栏小牛的菜单里点「重启以完成更新」")
                buttons(secondary: ("稍后自行重启", later), primary: ("立即重启", restart))
            }
        case .upToDate(let current, let build, let ok):
            UpdateHero(
                theme: .sun, kicker: "已经是最新版", number: current,
                caption: build.map { "(\($0)) · 刚刚检查过" } ?? "刚刚检查过", pose: .sunbathing
            )
            body {
                buttons(secondary: nil, primary: ("好", ok))
            }
        case .failed(let message, let ok):
            UpdateHero(theme: .sun, kicker: "没能完成更新", number: nil, caption: message, pose: .sunbathing)
            body {
                buttons(secondary: nil, primary: ("好", ok))
            }
        }
    }

    /// 头图下面：上 18、左右 20、下 20，块间隔 14。
    private func body(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s14, content: content)
            .padding(EdgeInsets(top: Spacing.s18, leading: Spacing.screen, bottom: Spacing.s20, trailing: Spacing.screen))
    }

    /// 底部按钮：次操作 surface 底墨字，主操作墨底浅字；只有一个时占满整行。
    private func buttons(secondary: (String, () -> Void)?, primary: (String, () -> Void)?) -> some View {
        HStack(spacing: Spacing.s10) {
            if let (title, action) = secondary {
                Button(title) { perform(action) }
                    .buttonStyle(.pill(.outline))
                    .keyboardShortcut(.cancelAction)
            }
            if let (title, action) = primary {
                Button(title) { perform(action) }
                    .buttonStyle(.pill(.ink))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, Spacing.s2)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(AppFont.caption).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func ratio(received: UInt64, expected: UInt64) -> Double {
        expected > 0 ? min(Double(received) / Double(expected), 1) : 0
    }

    /// 百分比，如「37%」。
    private static func percent(_ ratio: Double) -> String {
        "\(Int(ratio * 100))%"
    }

    /// 字节数写成「3.2 MB」。
    private static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }
}

/// 更新窗口的头图 (经典视觉，同 `BoldHero`)：210 高 (比页面头图矮，弹窗例外)，米白平底、下沿一条 line 分隔线；
/// 标题 17/700 墨色，大字 JetBrains Mono 54/700 墨色，说明行 12 muted。
/// 小牛 130×173 贴右下角，脚被下沿裁掉一截。`number` 为 nil 时 (出错) 只有标题与说明。
private struct UpdateHero: View {
    let theme: HeroTheme
    let kicker: String
    let number: String?
    let caption: String
    let pose: FloatingCowPose

    private static let height: CGFloat = 210

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Palette.bg
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker).font(AppFont.pageTitle).foregroundStyle(theme.classic.kicker).lineLimit(1).minimumScaleFactor(0.7)
                if let number {
                    Text(number)
                        .font(AppFont.num(54, .bold))
                        .tracking(-1.5)
                        .foregroundStyle(theme.classic.number)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.top, Spacing.s6)
                }
                SegmentedText(caption)
                    .font(AppFont.caption)
                    .foregroundStyle(theme.classic.secondary)
                    .padding(.top, number == nil ? Spacing.s10 : Spacing.s6)
            }
            .frame(maxWidth: 210, alignment: .leading)
            .padding(EdgeInsets(top: WindowChrome.Titlebar.hero.height + Spacing.s16, leading: Spacing.screen, bottom: 0, trailing: 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            FloatingCowBody(act: .pose(pose), motion: .live)
                .frame(width: 130, height: 173)
                .offset(x: -8, y: 22)
                .allowsHitTesting(false)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }
}

/// 更新内容卡片：白底、line 描边、圆角 10，「更新内容」11/600 muted 小标题，每条前面一个 accent 圆点；没有内容时不显示。
private struct UpdateNotesCard: View {
    let notes: [String]

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.s10) {
                Text("更新内容").font(AppFont.ui(11, .semibold)).foregroundStyle(Palette.muted)
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s10) {
                        Circle().fill(Palette.accent).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                        Text(note).font(AppFont.ui(13)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.r10))
            .overlay(RoundedRectangle(cornerRadius: Radius.r10).strokeBorder(Palette.line))
        }
    }
}

/// 下载进度：20 格小方块 (高 10、圆角 3，同首页进度格)，已下完的 money，正在下的那格 accent，其余 line 底。
private struct UpdateProgressBlocks: View {
    let ratio: Double

    private static let count = 20

    var body: some View {
        let filled = Int(ratio * Double(Self.count))
        HStack(spacing: Spacing.s3) {
            ForEach(0..<Self.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < filled ? Palette.money : index == filled ? Palette.accent : Palette.line)
                    .frame(height: 10)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("已下载 \(Int(ratio * 100))%")
    }
}
