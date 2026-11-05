import SwiftUI

/// 行内的小图标按钮 (编辑笔、垃圾桶)，默认 muted 色，12pt 图标放在 16pt 方块里。
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
        .buttonStyle(.plain)
        .help(help)
    }
}
