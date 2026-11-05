import SwiftUI

/// 设计稿子页面 (P3 至 P6) 的页头：左边返回箭头 + 标题 (15/700)，右边可放说明或操作，高 54，下沿一条分隔线。
/// 页头和系统红绿灯排在同一行 (见 `PageWindow`)，左边让出红绿灯的位置，返回箭头在红绿灯右边。
/// 顶层页面的返回就是关窗，下一级页面的返回回到上一级；esc 等同返回。
///
/// 用法：
/// - `PageHeader("目标", back: close)`
/// - 右侧放东西：`PageHeader("历史", back: close) { Text("按月倒序") }`
struct PageHeader<Trailing: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    private static var height: CGFloat { 54 }
    private static var iconSize: CGFloat { 16 }

    init(_ title: String, back: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.back = back
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Button(action: back) {
                HStack(spacing: Spacing.s8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: Self.iconSize, height: Self.iconSize)
                    Text(title).font(AppFont.sheetTitle).lineLimit(1)
                }
                .foregroundStyle(Palette.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("返回")
            Spacer(minLength: Spacing.s8)
            trailing()
        }
        .padding(.leading, WindowChrome.Titlebar.tall.leadingInset)
        .padding(.trailing, Spacing.screen)
        .frame(height: Self.height)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, back: @escaping () -> Void) {
        self.init(title, back: back) { EmptyView() }
    }
}

/// 页面里一组内容的小标题 (目标页「累计中 1」、设置页「钱与作息」)。
/// `count` 给了时在标题后面跟一个等宽小数字。
struct GroupLabel: View {
    let title: String
    var count: Int?
    var font: Font = AppFont.captionSemibold

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Text(title).font(font)
            if let count {
                Text("\(count)").font(AppFont.numSmall)
            }
        }
        .foregroundStyle(Palette.muted)
    }
}

/// 白底、line 描边的圆角卡片，里面一行一行用 `CardDivider` 隔开 (设置页、目标排队列表)。
struct CardBox<Content: View>: View {
    var radius: CGFloat = Radius.r10
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        VStack(spacing: 0, content: content)
            .background(Palette.card, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// 卡片里两行之间的分隔线。
struct CardDivider: View {
    var body: some View {
        Palette.line.frame(height: 1)
    }
}
