import SwiftUI

/// 按段换行的一行信息 (如「每秒 +¥0.0331 · 时薪 ¥119.05」)：放不下时只在「 · 」「，」后面换行，
/// 每一段 (如「时薪 ¥119.05」) 保持完整，不会被拆到两行。分隔符留在上一行末尾。
/// 某一段本身比整行还宽时，这一段才按字换行。
///
/// 用法：`SegmentedText("每秒 +¥0.0331 · 时薪 ¥119.05").font(AppFont.num(12, .bold))`
struct SegmentedText: View {
    let segments: [String]

    init(_ text: String) {
        segments = Self.split(text)
    }

    var body: some View {
        SegmentFlow {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Text(segment)
            }
        }
    }

    /// 在「 · 」「，」「、」后面切开，分隔符跟着前一段；切出的段去掉开头的空格。
    nonisolated static func split(_ text: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix(" · ") {
                current += " · "
                segments.append(current)
                current = ""
                index = text.index(index, offsetBy: 3)
                continue
            }
            let character = text[index]
            current.append(character)
            if character == "，" || character == "、" {
                segments.append(current)
                current = ""
            }
            index = text.index(after: index)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }
}

/// 把子视图一段段往右排，排不下换行；每段按自己的理想宽度排，比一行还宽的段按整行宽折行。
private struct SegmentFlow: Layout {
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width
            }
            y += row.height + lineSpacing
        }
    }

    /// 首行基线 = 第一段的基线，旁边的图标 (`iconOnTextBaseline`) 才能对齐第一行。
    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGFloat? {
        guard guide == .firstTextBaseline, let first = subviews.first else { return nil }
        let size = first.sizeThatFits(.unspecified)
        let fitted = size.width > bounds.width ? first.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)) : size
        return bounds.minY + first.dimensions(in: ProposedViewSize(fitted))[.firstTextBaseline]
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > width {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            if !row.items.isEmpty, row.width + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.items.append((index, size))
            row.width += size.width
            row.height = max(row.height, size.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
