import SwiftUI

/// 按段换行的一行信息 (如「每秒 +¥0.0331 · 时薪 ¥119.05」)：放不下时只在「 · 」「，」「、」处换行，
/// 每一段 (如「时薪 ¥119.05」) 保持完整，不会被拆到两行；换行处的分隔符不显示 (行尾挂着「·」很怪)。
/// 某一段本身比整行还宽时，这一段才按字换行。
///
/// 用法：`SegmentedText("每秒 +¥0.0331 · 时薪 ¥119.05").font(AppFont.num(12, .bold))`
struct SegmentedText: View {
    /// 交替排列：内容、分隔符、内容、分隔符…… (分隔符在偶数位之后的奇数位)。
    let pieces: [String]

    init(_ text: String) {
        pieces = Self.split(text)
    }

    var body: some View {
        SegmentFlow {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                Text(piece)
            }
        }
    }

    /// 切成「内容、分隔符、内容……」交替的数组，分隔符为「 · 」「，」「、」。
    nonisolated static func split(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix(" · ") {
                pieces += [current, " · "]
                current = ""
                index = text.index(index, offsetBy: 3)
                continue
            }
            let character = text[index]
            if character == "，" || character == "、" {
                pieces += [current, String(character)]
                current = ""
            } else {
                current.append(character)
            }
            index = text.index(after: index)
        }
        pieces.append(current)
        return pieces
    }
}

/// 把内容段一段段往右排，排不下换行；子视图按「内容、分隔符」交替。分隔符跟在前一段后面一起放，
/// 换行时上一行末尾的分隔符不显示 (挪到看不见的地方、给零大小)。比一行还宽的段按整行宽折行。
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
        var shown = Set<Int>()
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                shown.insert(item.index)
                x += item.size.width
            }
            y += row.height + lineSpacing
        }
        // 没排上的 (行尾的分隔符) 放到很远的地方、零大小，看不见。
        for index in subviews.indices where !shown.contains(index) {
            subviews[index].place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.minY), proposal: .zero)
        }
    }

    /// 首行基线 = 第一段的基线，旁边的图标 (`iconOnTextBaseline`) 才能对齐第一行。
    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGFloat? {
        guard guide == .firstTextBaseline, let first = subviews.first else { return nil }
        let size = fitted(first, width: bounds.width)
        return bounds.minY + first.dimensions(in: ProposedViewSize(size))[.firstTextBaseline]
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// 内容段在偶数位，分隔符在奇数位。一段 (带上它前面那个分隔符) 放得下就接在本行，否则换行、丢掉前面的分隔符。
    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in stride(from: 0, to: subviews.count, by: 2) {
            let size = fitted(subviews[index], width: width)
            let separator = index > 0 ? subviews[index - 1].sizeThatFits(.unspecified) : .zero
            if !row.items.isEmpty, row.width + separator.width + size.width <= width {
                row.items.append((index - 1, separator))
                row.width += separator.width
            } else if !row.items.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.items.append((index, size))
            row.width += size.width
            row.height = max(row.height, size.height, separator.height)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }

    /// 段的大小：放得下按理想宽度，比一行还宽时按整行宽折行。
    private func fitted(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let size = subview.sizeThatFits(.unspecified)
        return size.width > width ? subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) : size
    }
}
