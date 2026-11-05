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
    /// 彩纸在视图创建时随机生成一次，播放过程中不变。
    @State private var pieces = ConfettiPiece.random(count: 36)

    /// 整段动画的时长，结束后自动关掉。
    private static let duration: Duration = .seconds(3)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(started ? 0.15 : 0)
                if !reduceMotion {
                    ForEach(pieces) { piece in confetti(piece, in: geometry.size) }
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
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { started = true }
        }
        .task {
            try? await Task.sleep(for: Self.duration)
            // 被提前点掉或面板关了时任务已取消，不再重复结束。
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    /// 一片彩纸：从顶部上方落到底部以下，边落边转。
    private func confetti(_ piece: ConfettiPiece, in size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(piece.color)
            .frame(width: piece.width, height: piece.width * 0.45)
            .rotationEffect(.degrees(started ? piece.spin : 0))
            .position(x: size.width * piece.x, y: started ? size.height + 20 : -20)
            .animation(.easeIn(duration: piece.fall).delay(piece.delay), value: started)
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

    static func random(count: Int) -> [ConfettiPiece] {
        (0..<count).map { id in
            ConfettiPiece(
                id: id,
                x: .random(in: 0.04...0.96),
                width: .random(in: 7...11),
                color: palette.randomElement() ?? .orange,
                fall: .random(in: 1.4...2.2),
                delay: .random(in: 0...0.6),
                spin: .random(in: -540...540)
            )
        }
    }
}
