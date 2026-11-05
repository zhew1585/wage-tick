import SwiftUI
import WageCore

/// 目标达成庆祝动画 (PRD F9、AC-GPRG-04)：盖在今日概览面板上，彩纸落下、中间弹出达成文字。
/// 文字原样取自快照的 `GoalCelebration`。播放约 3 秒后自动消失，点一下提前关掉；结束时调用 `finish`。
/// 系统开了「减弱动态效果」时只显示文字，不落彩纸。
struct CelebrationView: View {
    let celebration: GoalCelebration
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false
    /// 彩纸在出现时随机生成一次，播放过程中不变。不放在 `@State` 初始值里：面板每 0.1 秒刷新都会重建视图值，初始值会被白算一遍。
    @State private var pieces: [ConfettiPiece] = []

    /// 整段动画的时长 (秒)，结束后自动关掉。
    private static let duration: Double = 3
    private static let confettiCount = 36
    /// 播放时盖在面板上的一层暗色。
    private static let dimOpacity = 0.15

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(started ? Self.dimOpacity : 0)
                if !reduceMotion && !pieces.isEmpty {
                    ConfettiLayer(pieces: pieces, size: geometry.size)
                }
                Text(celebration.message)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(started || reduceMotion ? 1 : 0.4)
                    .opacity(started ? 1 : 0)
                    .padding(.horizontal, 20)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .onAppear {
            pieces = ConfettiPiece.random(count: Self.confettiCount, within: Self.duration)
            // 文字弹出：带一点回弹。
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { started = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            // 被提前点掉或面板关了时任务已取消，不再重复结束。
            guard !Task.isCancelled else { return }
            finish()
        }
    }
}

/// 一层彩纸：出现后每片从顶部上方落到底部以下，边落边转。
/// 单独成一个视图，让彩纸先以起点插入、在自己的 onAppear 里再开始下落，否则插入时就已在终点。
private struct ConfettiLayer: View {
    let pieces: [ConfettiPiece]
    let size: CGSize

    @State private var fallen = false
    /// 彩纸起点在顶部上方、终点在底部下方的距离，进出都不露边。
    private static let margin: CGFloat = 20

    var body: some View {
        ForEach(pieces) { piece in
            RoundedRectangle(cornerRadius: 1.5)
                .fill(piece.color)
                .frame(width: piece.width, height: piece.width * 0.45)
                .rotationEffect(.degrees(fallen ? piece.spin : 0))
                .position(x: size.width * piece.x, y: fallen ? size.height + Self.margin : -Self.margin)
                .animation(.easeIn(duration: piece.fall).delay(piece.delay), value: fallen)
        }
        .onAppear { fallen = true }
    }
}

/// 一片彩纸的随机参数。
private struct ConfettiPiece: Identifiable {
    let id: Int
    /// 水平位置，占面板宽度的比例。
    let x: CGFloat
    let width: CGFloat
    let color: Color
    /// 落到底部用时 (秒) 与起落延迟 (秒)，两者之和不超过整段动画时长。
    let fall: Double
    let delay: Double
    /// 落下过程中转过的角度。
    let spin: Double

    private static let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .pink, .purple]

    /// `count` 片彩纸，都在 `duration` 秒内落完：延迟至多占 1/5，下落用时占剩下的一半到全部。
    static func random(count: Int, within duration: Double) -> [ConfettiPiece] {
        let maxDelay = duration / 5
        let maxFall = duration - maxDelay
        return (0..<count).map { id in
            ConfettiPiece(
                id: id,
                x: .random(in: 0.04...0.96),
                width: .random(in: 7...11),
                color: palette.randomElement() ?? .orange,
                fall: .random(in: maxFall / 2...maxFall),
                delay: .random(in: 0...maxDelay),
                spin: .random(in: -540...540)
            )
        }
    }
}
