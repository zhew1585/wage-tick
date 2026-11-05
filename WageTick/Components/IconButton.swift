import SwiftUI

/// 行内的小图标按钮 (编辑笔、垃圾桶)，默认 muted 色，12pt 图标放在 16pt 方块里。
/// 悬停、按下时外扩一圈圆角底 (`.highlight`)，不可用时没有反馈。
/// 用法：`IconButton(systemName: "pencil", help: "编辑") { … }`
struct IconButton: View {
    let systemName: String
    let help: String
    var color: Color = Palette.muted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(color)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.highlight(radius: Radius.r4, outset: 3))
        .help(help)
    }
}
