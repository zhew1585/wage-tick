import SwiftUI

// 发薪当天 (和目标达成插播跳跃时) 撒在小牛周围的彩带。和木偶一样只由「第几秒」决定，
// 静止与离屏预览用 SwiftUI 画，实时播放交给 Core Animation (`ConfettiLive`)。

/// 发薪当天撒在小牛周围的一片彩带，位置按设计稿 Zsosp 换算到气泡左上角为原点。
/// 动起来时每片错开节拍上下飘、左右摆、一闪一闪。
struct CowConfetti {
    /// 某一刻相对设计稿位置的变化。
    struct Motion {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        /// 在设计稿角度之外再转的角度 (度，顺时针为正)。
        var spin: Double = 0
        var scale: CGFloat = 1
    }

    /// 飘一个来回的秒数，是小牛一跳的两倍，两者一起首尾相接。
    static let period: TimeInterval = 2 * CowRigs.payday.period

    let icon: Phosphor
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let rotation: Double
    let color: Color

    static let all = [
        CowConfetti(icon: .confettiBold, x: -42, y: -26, size: 22, rotation: -10, color: Palette.accent),
        CowConfetti(icon: .starFourBold, x: 60, y: -40, size: 14, rotation: 0, color: Palette.coin),
        CowConfetti(icon: .sparkleBold, x: 136, y: -31, size: 14, rotation: 0, color: Palette.coin),
        CowConfetti(icon: .sparkleBold, x: 146, y: 97, size: 14, rotation: 0, color: Palette.accent),
        CowConfetti(icon: .coinBold, x: -30, y: 123, size: 14, rotation: 15, color: Palette.coin),
        CowConfetti(icon: .coinBold, x: -12, y: 169, size: 14, rotation: -20, color: Palette.coinDeep),
        CowConfetti(icon: .coinsBold, x: -32, y: 214, size: 14, rotation: 0, color: Palette.coinDeep),
    ]

    /// 第 `index` 片在第 `time` 秒的样子，按 `period` 循环。
    static func motion(_ index: Int, at time: TimeInterval) -> Motion {
        let beat = 2 * .pi * time / period + Double(index) * 1.3
        let wave = sin(beat)
        let twinkle = CGFloat(sin(2 * beat + 0.8))
        return Motion(dx: 2 * twinkle, dy: 4 * CGFloat(wave), spin: 16 * wave, scale: 1 + 0.18 * twinkle)
    }
}

/// 彩带层：静止与离屏预览用 SwiftUI 画，实时播放交给 `ConfettiLiveLayers`。
/// 原点在气泡左上角，各片画在原点四周 (大多在气泡外)。
struct Confetti: View {
    let motion: CowMotion

    var body: some View {
        Group {
            switch motion {
            case .live:
                ConfettiLive()
            case .frozen(let time):
                ZStack(alignment: .topLeading) {
                    ForEach(CowConfetti.all.indices, id: \.self) { index in
                        piece(CowConfetti.all[index], time.map { CowConfetti.motion(index, at: $0) } ?? .init())
                    }
                }
                .frame(width: 0, height: 0, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func piece(_ piece: CowConfetti, _ motion: CowConfetti.Motion) -> some View {
        PhosphorIcon(piece.icon, size: piece.size)
            .foregroundStyle(piece.color)
            .scaleEffect(motion.scale)
            .rotationEffect(.degrees(piece.rotation + motion.spin))
            .offset(x: piece.x + motion.dx, y: piece.y + motion.dy)
    }
}
