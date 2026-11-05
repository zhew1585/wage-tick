import SwiftUI

/// 设计稿 Chip：浅色胶囊底 + 6pt 圆点 + 11/600 文字，左右内边距 9、上下 3。
/// 用法：`Chip("上班中", tone: .money)`；休息日用 `.accent`，白干中用 `.loss`。
struct Chip: View {
    enum Tone {
        case money, accent, loss

        fileprivate var foreground: Color {
            switch self {
            case .money: Palette.money
            case .accent: Palette.accent
            case .loss: Palette.loss
            }
        }

        fileprivate var background: Color {
            switch self {
            case .money: Palette.moneySoft
            case .accent: Palette.accentSoft
            case .loss: Palette.lossSoft
            }
        }
    }

    private static let dotSize: CGFloat = 6

    let text: String
    let tone: Tone

    init(_ text: String, tone: Tone = .money) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tone.foreground).frame(width: Self.dotSize, height: Self.dotSize)
            Text(text).font(AppFont.chip).foregroundStyle(tone.foreground)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(tone.background, in: Capsule())
    }
}
