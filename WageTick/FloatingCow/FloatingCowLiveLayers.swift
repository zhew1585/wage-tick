import AppKit
import QuartzCore
import SwiftUI

// 悬浮小牛动画的实时播放：把一个循环里的动作 (`CowRig.frame(at:)`、`CowConfetti.motion`) 按 30 帧每秒采样成关键帧，
// 交给 Core Animation 无限循环。插值和绘制都在系统渲染进程里做，App 主线程每帧什么都不用干。
// 不用 SwiftUI 的 TimelineView 逐帧刷：那样每帧都要走一遍浮窗的布局与提交，常驻桌面一整天太费电 (Debug 构建实测多占约 10% CPU)。

/// 木偶 (实时版)，画法与 `RigStill` 一致。换动作时由上层用 `.id` 换一个新视图，这里不处理换木偶。
struct RigLive: NSViewRepresentable {
    let rig: CowRig

    func makeNSView(context: Context) -> LoopLayerView {
        LoopLayerView { [rig] root, size in RigLayers.build(rig, in: root, size: size) }
    }

    func updateNSView(_ view: LoopLayerView, context: Context) {}
}

/// 彩带 (实时版)。图层画在一个盖住彩带范围的框里，框的左上角在气泡左上角往外 `margin` 处。
struct ConfettiLive: View {
    /// 彩带最远伸出气泡左、上边约 42 点，右、下边也够放下最右、最下的一片。
    static let margin: CGFloat = 60
    static let box = CGSize(width: 280, height: 320)

    var body: some View {
        ConfettiLayerView()
            .frame(width: Self.box.width, height: Self.box.height)
            .offset(x: -Self.margin, y: -Self.margin)
    }

    private struct ConfettiLayerView: NSViewRepresentable {
        func makeNSView(context: Context) -> LoopLayerView {
            LoopLayerView { root, _ in ConfettiLayers.build(in: root, origin: CGPoint(x: margin, y: margin)) }
        }

        func updateNSView(_ view: LoopLayerView, context: Context) {}
    }
}

/// 放循环动画图层的 NSView：坐标与 SwiftUI 一致 (左上为原点、y 向下、顺时针转为正)。
/// 尺寸定下来后搭一次图层；换到不同分辨率的屏幕时更新图层清晰度。不接鼠标，点击照旧交给浮窗。
final class LoopLayerView: NSView {
    private let build: @MainActor (CALayer, CGSize) -> Void
    private var builtSize: CGSize?

    init(build: @escaping @MainActor (CALayer, CGSize) -> Void) {
        self.build = build
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不从 nib 加载") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard let layer, bounds.width > 0, bounds.size != builtSize else { return }
        builtSize = bounds.size
        layer.sublayers = nil
        build(layer, bounds.size)
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        func apply(_ layer: CALayer) {
            layer.contentsScale = scale
            layer.sublayers?.forEach(apply)
        }
        layer?.sublayers?.forEach(apply)
    }
}

// MARK: 搭图层

@MainActor
private enum RigLayers {
    /// 搭出木偶与脚下影子，装上一个循环的关键帧。只有真的会变的属性才装动画。
    static func build(_ rig: CowRig, in root: CALayer, size: CGSize) {
        let period = rig.period
        let frames = Loop.sample(period: period, rig.frame(at:))

        if let width = rig.shadowWidth {
            let shadows = frames.map { CowRig.shadow(lift: -$0.whole.offset.height, width: width) }
            let shadow = CAShapeLayer()
            shadow.bounds = CGRect(x: 0, y: 0, width: width, height: CowRig.shadowHeight)
            shadow.position = CGPoint(x: size.width / 2, y: size.height - CowRig.shadowLift)
            shadow.path = CGPath(ellipseIn: shadow.bounds, transform: nil)
            shadow.fillColor = NSColor(Palette.ink).cgColor
            shadow.opacity = Float(shadows[0].opacity)
            animate(shadow, "transform.scale.x", shadows.map(\.scale), period: period)
            animate(shadow, "opacity", shadows.map(\.opacity), period: period)
            root.addSublayer(shadow)
        }

        // 整只：以脚底中点为锚。
        let puppet = fullLayer(size: size, pivot: .bottom)
        animate(puppet, frames.map(\.whole), period: period)
        root.addSublayer(puppet)

        for part in rig.parts {
            let layer = fullLayer(size: size, pivot: part.pivot)
            layer.contents = NSImage(named: part.image)
            layer.contentsGravity = .resize
            layer.minificationFilter = .trilinear
            animate(layer, frames.map { $0[part.image] }, period: period)
            // 跟着别的层走：外面套一层，装上那一层的动作。
            if let leader = part.follows.flatMap(rig.part) {
                let follower = fullLayer(size: size, pivot: leader.pivot)
                animate(follower, frames.map { $0[leader.image] }, period: period)
                follower.addSublayer(layer)
                puppet.addSublayer(follower)
            } else {
                puppet.addSublayer(layer)
            }
        }
    }

    /// 和小牛框一样大的图层，锚点设到关节上 (锚点变了位置要跟着挪，图层才留在原处)。
    private static func fullLayer(size: CGSize, pivot: UnitPoint) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.anchorPoint = CGPoint(x: pivot.x, y: pivot.y)
        layer.position = CGPoint(x: pivot.x * size.width, y: pivot.y * size.height)
        return layer
    }

    /// 装上一层的变换与透明度关键帧；整个循环都不变的就直接设成静态值。
    private static func animate(_ layer: CALayer, _ motions: [PartMotion], period: TimeInterval) {
        let transforms = motions.map(transform)
        if Set(motions.map(\.angle)).count > 1 || Set(motions.map(\.offset.width)).count > 1
            || Set(motions.map(\.offset.height)).count > 1 || Set(motions.map(\.scale.width)).count > 1
            || Set(motions.map(\.scale.height)).count > 1 {
            animate(layer, "transform", transforms.map { NSValue(caTransform3D: $0) }, period: period)
        } else {
            layer.transform = transforms[0]
        }
        let opacities = motions.map(\.opacity)
        layer.opacity = Float(opacities[0])
        if Set(opacities).count > 1 {
            animate(layer, "opacity", opacities, period: period)
        }
    }

    private static func animate(_ layer: CALayer, _ keyPath: String, _ values: [Any], period: TimeInterval) {
        layer.add(Loop.animation(keyPath, values, period: period), forKey: keyPath)
    }

    /// 先缩放、再旋转 (都绕锚点)，最后平移，与 `RigStill` 的顺序一致。
    private static func transform(_ motion: PartMotion) -> CATransform3D {
        let scale = CATransform3DMakeScale(motion.scale.width, motion.scale.height, 1)
        let rotate = CATransform3DConcat(scale, CATransform3DMakeRotation(radians(motion.angle), 0, 0, 1))
        return CATransform3DConcat(rotate, CATransform3DMakeTranslation(motion.offset.width, motion.offset.height, 0))
    }
}

@MainActor
private enum ConfettiLayers {
    /// 每片彩带一个图层 (图标预先着色成位图)，中心在设计稿位置，绕中心转、缩放。`origin` 是气泡左上角在框里的位置。
    static func build(in root: CALayer, origin: CGPoint) {
        for (index, piece) in CowConfetti.all.enumerated() {
            let frames = Loop.sample(period: CowConfetti.period) { CowConfetti.motion(index, at: $0) }
            let layer = CALayer()
            layer.bounds = CGRect(x: 0, y: 0, width: piece.size, height: piece.size)
            layer.position = CGPoint(x: origin.x + piece.x + piece.size / 2, y: origin.y + piece.y + piece.size / 2)
            layer.contents = icon(piece)
            layer.contentsGravity = .resizeAspect
            layer.add(Loop.animation("transform", frames.map { motion in
                let move = CATransform3DMakeTranslation(motion.dx, motion.dy, 0)
                let spin = CATransform3DRotate(move, radians(piece.rotation + motion.spin), 0, 0, 1)
                return NSValue(caTransform3D: CATransform3DScale(spin, motion.scale, motion.scale, 1))
            }, period: CowConfetti.period), forKey: nil)
            root.addSublayer(layer)
        }
    }

    /// 图标按片的颜色着色、按 3 倍渲染成位图 (够任何屏幕用)。
    private static func icon(_ piece: CowConfetti) -> CGImage? {
        let renderer = ImageRenderer(content: PhosphorIcon(piece.icon, size: piece.size).foregroundStyle(piece.color))
        renderer.scale = 3
        return renderer.cgImage
    }
}

/// 循环关键帧：采样与动画。
private enum Loop {
    /// 一个循环按 `CowRig.sampleInterval` 采样，首尾各取一帧 (首尾相同，循环无缝)。
    static func sample<Value>(period: TimeInterval, _ value: (TimeInterval) -> Value) -> [Value] {
        let count = Int((period / CowRig.sampleInterval).rounded())
        return (0...count).map { value(period * Double($0) / Double(count)) }
    }

    /// 无限循环的线性关键帧动画，`values` 是 `sample` 取出的一个循环。
    static func animation(_ keyPath: String, _ values: [Any], period: TimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.duration = period
        animation.calculationMode = .linear
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        return animation
    }
}

private func radians(_ degrees: Double) -> Double {
    degrees * .pi / 180
}
