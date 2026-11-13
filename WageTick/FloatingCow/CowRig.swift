import SwiftUI
import WageCore

// 悬浮小牛的动作系统。每个动作是一套木偶 (`CowRig`)：几层整幅透明素材 + 各自的关节 + 一个循环里每一刻每层怎么动。
// 动作只由「第几秒」决定 (`CowRig.frame(at:)`)，同一份数据有两种画法：
// 实时播放交给 Core Animation (`FloatingCowLiveLayers`，预先采样成一个循环的关键帧，App 每帧不用干活)；
// 静止姿势与离屏预览的逐帧渲染用这里的 SwiftUI 视图 (`RigStill`)。
// 各动作的定义见 `CowRigs.swift`。

/// 浮窗上小牛此刻在做的动作：快照给的姿势，或外壳插播的一次性反应。
enum CowAct: Hashable {
    case pose(FloatingCowPose)
    /// 刚记了一笔扣钱：哇哇大哭 (插播)。
    case crying
}

/// 动画怎么画：实时循环播放，或停在某一秒 (nil 为静止姿势，各层归位)。
enum CowMotion {
    case live
    case frozen(TimeInterval?)

    static let rest = CowMotion.frozen(nil)
}

/// 一层素材在某一刻的变化：先绕关节缩放、旋转，再平移；另有透明度 (汗珠、泪滴一闪一闪用)。
struct PartMotion: Equatable, Sendable {
    /// 度，顺时针为正。
    var angle: Double = 0
    /// 点，y 向下为正。
    var offset: CGSize = .zero
    var scale = CGSize(width: 1, height: 1)
    var opacity: Double = 1

    static let identity = PartMotion()
}

/// 木偶的一层。`follows` 指定跟着哪一层的动作走 (如金币跟着右手转)，但画在自己的层序上 (金币压在头前面)。
struct RigPart: Sendable {
    let image: String
    /// 关节，归一化到整幅图。
    let pivot: UnitPoint
    var follows: String?
}

/// 某一刻的整套姿势：整只 (以脚底中点为锚) 与各层的变化，没写到的层不动。
struct RigFrame: Sendable {
    var whole = PartMotion.identity
    var parts: [String: PartMotion] = [:]

    subscript(_ image: String) -> PartMotion {
        get { parts[image] ?? .identity }
        set { parts[image] = newValue }
    }
}

/// 一个动作：层 (从后到前)、一个循环的时长、每一刻的姿势。
struct CowRig: Sendable {
    let parts: [RigPart]
    let period: TimeInterval
    /// 脚下影子的宽度 (点，按 120×160 的小牛框)；nil 时不画影子。跳起时 (`whole.offset.height` 为负) 自动变小变淡。
    var shadowWidth: CGFloat? = 52
    let motion: @Sendable (TimeInterval) -> RigFrame

    /// 采样间隔：实时播放的关键帧、离屏预览的逐帧都按每秒 30 帧取。
    static let sampleInterval: TimeInterval = 1.0 / 30
    static let shadowHeight: CGFloat = 7
    /// 影子中心离小牛框底边的距离。
    static let shadowLift: CGFloat = 2 + shadowHeight / 2

    /// 第 `time` 秒的姿势，按 `period` 循环。
    func frame(at time: TimeInterval) -> RigFrame {
        motion(time.truncatingRemainder(dividingBy: period))
    }

    func part(_ image: String) -> RigPart? {
        parts.first { $0.image == image }
    }

    /// 影子随跳起高度 (点) 变化的横向缩放与不透明度。
    static func shadow(lift: CGFloat, width: CGFloat) -> (scale: CGFloat, opacity: Double) {
        (max(0.3, (width - 2.4 * lift) / width), max(0.04, 0.16 - 0.012 * Double(lift)))
    }
}

/// 全身小牛：按动作取木偶。
struct FloatingCowBody: View {
    let act: CowAct
    let motion: CowMotion

    var body: some View {
        RigView(rig: CowRigs.rig(for: act), motion: motion)
    }
}

/// 木偶：实时播放 (Core Animation) 或停在某一秒 (SwiftUI)。
struct RigView: View {
    let rig: CowRig
    let motion: CowMotion

    var body: some View {
        Group {
            switch motion {
            // 图层只在创建时搭一次，换了动作 (如发薪日点了被迫营业，撒钱换成冒汗) 要换一个新视图重搭。
            case .live: RigLive(rig: rig).id(rig.parts.map(\.image))
            case .frozen(let time): RigStill(rig: rig, frame: time.map(rig.frame(at:)) ?? RigFrame())
            }
        }
        .accessibilityElement()
        .accessibilityLabel("小牛")
    }
}

/// 把木偶按某一刻的姿势画出来 (静止与离屏预览用)。每层整幅叠在同一个框里，绕各自关节变化。
struct RigStill: View {
    let rig: CowRig
    let frame: RigFrame

    var body: some View {
        let lift = -frame.whole.offset.height
        ZStack {
            ForEach(rig.parts, id: \.image) { part in
                let layer = layer(part)
                if let leader = part.follows.flatMap(rig.part) {
                    layer.modifier(PartEffect(motion: frame[leader.image], pivot: leader.pivot))
                } else {
                    layer
                }
            }
        }
        .modifier(PartEffect(motion: frame.whole, pivot: .bottom))
        .background(alignment: .bottom) {
            if let width = rig.shadowWidth {
                let shadow = CowRig.shadow(lift: lift, width: width)
                Ellipse()
                    .fill(Palette.ink.opacity(shadow.opacity))
                    .frame(width: width * shadow.scale, height: CowRig.shadowHeight)
                    .offset(y: CowRig.shadowHeight / 2 - CowRig.shadowLift)
            }
        }
    }

    private func layer(_ part: RigPart) -> some View {
        Image(part.image)
            .resizable()
            .interpolation(.high)
            .modifier(PartEffect(motion: frame[part.image], pivot: part.pivot))
    }
}

/// 绕 `pivot` 缩放、旋转，再平移，最后乘上透明度。
private struct PartEffect: ViewModifier {
    let motion: PartMotion
    let pivot: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: motion.scale.width, y: motion.scale.height, anchor: pivot)
            .rotationEffect(.degrees(motion.angle), anchor: pivot)
            .offset(motion.offset)
            .opacity(motion.opacity)
    }
}
