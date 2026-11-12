import SwiftUI
import WageCore

/// 各动作的木偶定义：每个姿势都拆了层、有专门的循环动作。
/// 拆层素材在 `Assets.xcassets/FloatingCow/<姿势>Rig`，拆图记录见 `docs/assets/cow-rig/`。
/// 各层转动幅度别超过约 ±15°，再大关节处的补画会露馅。
enum CowRigs {
    static func rig(for act: CowAct) -> CowRig {
        switch act {
        case .pose(.paid): payday
        case .pose(.working): working
        case .pose(.excited): excited
        case .pose(.lyingFlat): lyingFlat
        case .pose(.sweating): sweating
        case .pose(.yawning): yawning
        case .pose(.eating): eating
        case .pose(.sunbathing): sunbathing
        case .crying: crying
        }
    }

    // MARK: 上班中：端咖啡

    /// `WorkRig` 6 层，4 秒一轮：轻轻呼吸，头慢慢晃，尾巴慢甩；第 1.2 秒抬杯喝一口 (端杯的手臂往上转 12°)，第 3 秒眨一下眼。
    static let working: CowRig = {
        let tail = "CowWorkTail", body = "CowWorkBody", armLeft = "CowWorkArmLeft", armRight = "CowWorkArmRight"
        let head = "CowWorkHead", blink = "CowWorkHeadBlink"
        let period = 4.0
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(361, 1127)),
                RigPart(image: body, pivot: pivot(535, 1000)),
                RigPart(image: armLeft, pivot: pivot(413, 746)),
                RigPart(image: armRight, pivot: pivot(639, 749)),
                RigPart(image: head, pivot: pivot(542, 690)),
                RigPart(image: blink, pivot: pivot(542, 690), follows: head),
            ],
            period: period
        ) { time in
            let turn = 2 * Double.pi * time / period
            var frame = breath(time, period: period)
            frame[head].angle = 3 * sin(turn)
            frame[tail].angle = 12 * sin(2 * turn)
            frame[armLeft].angle = 2 * sin(turn + 1)
            frame[armRight].angle = -12 * pulse(time, start: 1.2, rise: 0.35, hold: 0.5, fall: 0.4)
            frame[blink].opacity = blinking(time, at: 3)
            return frame
        }
    }()

    // MARK: 快发薪：兴奋握拳

    /// `ExcitedRig` 6 层，0.8 秒一轮：原地连蹦两下，双拳一上一下交替捶，头跟着点，尾巴快甩；每两轮眨一次眼 (周期 1.6 秒)。
    static let excited: CowRig = {
        let tail = "CowExcitedTail", body = "CowExcitedBody", armLeft = "CowExcitedArmLeft", armRight = "CowExcitedArmRight"
        let head = "CowExcitedHead", blink = "CowExcitedHeadBlink"
        let period = 1.6
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(771, 1065)),
                RigPart(image: body, pivot: pivot(534, 1023)),
                RigPart(image: armLeft, pivot: pivot(414, 787)),
                RigPart(image: armRight, pivot: pivot(662, 786)),
                RigPart(image: head, pivot: pivot(531, 746)),
                RigPart(image: blink, pivot: pivot(531, 746), follows: head),
            ],
            period: period
        ) { time in
            let beat = 2 * Double.pi * time / (period / 4)
            var frame = RigFrame()
            frame.whole.offset.height = -3 * CGFloat(abs(sin(beat / 2)))
            frame[armLeft].angle = 10 * sin(beat / 2)
            frame[armRight].angle = 10 * sin(beat / 2)
            frame[head].angle = 4 * sin(beat / 2 - 0.6)
            frame[tail].angle = 18 * sin(beat)
            frame[blink].opacity = blinking(time, at: 1.1)
            return frame
        }
    }()

    // MARK: 未上班：打哈欠

    /// `YawningRig` 6 层，4 秒一轮：第 0.5 秒起打一个长哈欠 (整只往上伸 3%，头往后仰，伸懒腰的手臂再往外伸，捂嘴的手跟着抬)，
    /// 其余时间慢慢呼吸、手臂轻晃；泪滴一闪一闪，尾巴慢甩。
    static let yawning: CowRig = {
        let tail = "CowYawningTail", body = "CowYawningBody", armUp = "CowYawningArmUp"
        let head = "CowYawningHead", armMouth = "CowYawningArmMouth", tear = "CowYawningTear"
        let period = 4.0
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(411, 1090)),
                RigPart(image: body, pivot: pivot(560, 1010)),
                RigPart(image: armUp, pivot: pivot(705, 739)),
                RigPart(image: head, pivot: pivot(550, 729)),
                RigPart(image: armMouth, pivot: pivot(416, 782)),
                RigPart(image: tear, pivot: pivot(688, 431), follows: head),
            ],
            period: period
        ) { time in
            let turn = 2 * Double.pi * time / period
            let yawn = pulse(time, start: 0.5, rise: 0.8, hold: 1.1, fall: 0.8)
            var frame = breath(time, period: period)
            frame.whole.scale.height += 0.03 * yawn
            frame[head].angle = -5 * yawn + 1.5 * sin(turn)
            frame[armUp].angle = 8 * yawn + 3 * sin(2 * turn)
            frame[armMouth].angle = 4 * yawn
            frame[tear].offset.height = 0.4 * CGFloat(sin(2 * turn))
            frame[tear].opacity = 0.75 + 0.25 * sin(4 * turn)
            frame[tail].angle = 10 * sin(turn)
            return frame
        }
    }()

    // MARK: 干饭中：捧碗干饭

    /// `EatingRig` 7 层，2 秒一轮：筷子一下下往嘴里送 (一轮两口)，头点着嚼，饭粒从嘴边往上冒再淡出，
    /// 捧碗的手轻晃，尾巴甩，第 1.4 秒眨眼。闭眼头紧贴在头上面、压在拿筷子的手臂下面。
    static let eating: CowRig = {
        let tail = "CowEatingTail", body = "CowEatingBody", armBowl = "CowEatingArmBowl", head = "CowEatingHead"
        let blink = "CowEatingHeadBlink", armChopsticks = "CowEatingArmChopsticks", rice = "CowEatingRice"
        let headPivot = pivot(516, 705)
        let period = 2.0
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(360, 1105)),
                RigPart(image: body, pivot: pivot(512, 1010)),
                RigPart(image: armBowl, pivot: pivot(635, 782)),
                RigPart(image: head, pivot: headPivot),
                RigPart(image: blink, pivot: headPivot, follows: head),
                RigPart(image: armChopsticks, pivot: pivot(392, 780)),
                RigPart(image: rice, pivot: pivot(474, 639), follows: head),
            ],
            period: period
        ) { time in
            let turn = 2 * Double.pi * time / period
            let bite = max(0, sin(2 * turn))
            var frame = breath(time, period: period)
            frame[armChopsticks].angle = 9 * bite - 3
            frame[head].angle = 3 * sin(4 * turn)
            frame[armBowl].angle = 3 * sin(turn)
            let rise = CGFloat((2 * time / period).truncatingRemainder(dividingBy: 1))
            frame[rice].offset.height = -1.5 * rise
            frame[rice].opacity = Double(min(1, 5 * rise, 3 * (1 - rise)))
            frame[blink].opacity = blinking(time, at: 1.4)
            frame[tail].angle = 12 * sin(2 * turn)
            return frame
        }
    }()

    // MARK: 休息日：戴墨镜晒太阳

    /// `SunbathingRig` 5 层，2.4 秒一轮：挥手 (一轮两下)，第 1.2 秒抬杯喝一口，头和整只跟着节奏左右轻摆，尾巴甩。
    static let sunbathing: CowRig = {
        let tail = "CowSunbathingTail", body = "CowSunbathingBody", armWave = "CowSunbathingArmWave"
        let armDrink = "CowSunbathingArmDrink", head = "CowSunbathingHead"
        let period = 2.4
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(350, 1105)),
                RigPart(image: body, pivot: pivot(503, 1010)),
                RigPart(image: armWave, pivot: pivot(379, 755)),
                RigPart(image: armDrink, pivot: pivot(630, 804)),
                RigPart(image: head, pivot: pivot(514, 741)),
            ],
            period: period
        ) { time in
            let turn = 2 * Double.pi * time / period
            var frame = RigFrame()
            frame.whole.angle = 1.2 * sin(turn)
            frame[armWave].angle = 12 * sin(2 * turn)
            frame[armDrink].angle = -10 * pulse(time, start: 1.2, rise: 0.3, hold: 0.35, fall: 0.3)
            frame[head].angle = 4 * sin(turn + 0.5)
            frame[tail].angle = 15 * sin(2 * turn)
            return frame
        }
    }()

    // MARK: 已下班：躺平

    /// `LyingFlatRig` 5 层，4 秒一轮：慢慢呼吸，翘起的腿一晃一晃 (一轮两下)，头微微点，尾巴慢甩，第 2.6 秒眨眼。
    static let lyingFlat: CowRig = {
        let tail = "CowLyingFlatTail", body = "CowLyingFlatBody", leg = "CowLyingFlatLegUp"
        let head = "CowLyingFlatHead", blink = "CowLyingFlatHeadBlink"
        let period = 4.0
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(380, 1347)),
                RigPart(image: body, pivot: pivot(573, 1296)),
                RigPart(image: leg, pivot: pivot(619, 1349)),
                RigPart(image: head, pivot: pivot(379, 1191)),
                RigPart(image: blink, pivot: pivot(379, 1191), follows: head),
            ],
            period: period,
            shadowWidth: 104
        ) { time in
            let turn = 2 * Double.pi * time / period
            var frame = breath(time, period: period)
            frame[leg].angle = 7 * sin(2 * turn)
            frame[head].angle = 2 * sin(turn)
            frame[tail].angle = 10 * sin(2 * turn + 1)
            frame[blink].opacity = blinking(time, at: 2.6)
            return frame
        }
    }()

    // MARK: 白干：抱电脑冒汗

    /// 两侧往外甩的汗珠 (源图像素坐标里的位置)；额头、脸上的另算，跟着头往下淌。
    private static let flyingSweat: Set<Int> = [1, 2, 6, 7, 8]

    /// `SweatingRig` 12 层，1.2 秒一轮：整只轻颤，电脑跟着敲键盘一上一下 (一轮 6 下)，头发抖，尾巴甩；
    /// 8 颗汗珠错开节拍：两侧的往外飞 2 点并淡出，额头脸上的往下淌 1.5 点并淡出，然后重来。
    static let sweating: CowRig = {
        let tail = "CowSweatingTail", body = "CowSweatingBody", laptop = "CowSweatingLaptop", head = "CowSweatingHead"
        let drops: [(image: String, x: CGFloat, y: CGFloat)] = [
            (1, 254, 440), (2, 262, 505), (3, 402, 560), (4, 459, 280),
            (5, 686, 344), (6, 787, 560), (7, 903, 545), (8, 923, 477),
        ].map { ("CowSweatingSweat\($0.0)", $0.1, $0.2) }
        let headPivot = pivot(580, 716)
        // 汗珠往外飞的方向：从脸中间指向汗珠。
        let face = CGPoint(x: 580, y: 470)
        let period = 1.2
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(412, 1131)),
                RigPart(image: body, pivot: pivot(575, 1050)),
                RigPart(image: laptop, pivot: pivot(610, 900)),
                RigPart(image: head, pivot: headPivot),
            ] + drops.map { RigPart(image: $0.image, pivot: pivot($0.x, $0.y), follows: head) },
            period: period
        ) { time in
            let turn = 2 * Double.pi * time / period
            var frame = RigFrame()
            frame.whole.offset.width = 0.4 * CGFloat(sin(4 * turn))
            frame[laptop].offset.height = 0.8 * CGFloat(sin(6 * turn))
            frame[head].angle = 2 * sin(3 * turn)
            frame[tail].angle = 12 * sin(2 * turn)
            for (index, drop) in drops.enumerated() {
                let progress = CGFloat((time / period + Double(index) / Double(drops.count)).truncatingRemainder(dividingBy: 1))
                if flyingSweat.contains(index + 1) {
                    let dx = drop.x - face.x, dy = drop.y - face.y
                    let length = max(1, (dx * dx + dy * dy).squareRoot())
                    frame[drop.image].offset = CGSize(width: 2 * progress * dx / length, height: 2 * progress * dy / length)
                } else {
                    frame[drop.image].offset.height = 1.5 * progress
                }
                frame[drop.image].opacity = Double(min(1, 6 * progress, 4 * (1 - progress)))
            }
            return frame
        }
    }()

    // MARK: 插播：被扣钱大哭

    /// `CryingRig` 6 层，1 秒一轮：整只抽泣 (一轮两下纵向一缩)，头左右摇，钱包跟着抖，
    /// 两道泪流以眼角为锚纵向伸缩 (0.88 到 1.06 倍) 并跟着头，尾巴耷拉着慢甩。
    static let crying: CowRig = {
        let tail = "CowCryingTail", body = "CowCryingBody", wallet = "CowCryingWallet", head = "CowCryingHead"
        let tearLeft = "CowCryingTearLeft", tearRight = "CowCryingTearRight"
        let period = 1.0
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(350, 1158)),
                RigPart(image: body, pivot: pivot(520, 1050)),
                RigPart(image: wallet, pivot: pivot(519, 950)),
                RigPart(image: head, pivot: pivot(520, 745)),
                RigPart(image: tearLeft, pivot: pivot(413, 469), follows: head),
                RigPart(image: tearRight, pivot: pivot(630, 469), follows: head),
            ],
            period: period
        ) { time in
            let turn = 2 * Double.pi * time / period
            let sob = CGFloat(max(0, sin(2 * turn)))
            var frame = RigFrame()
            frame.whole.scale = CGSize(width: 1 + 0.01 * sob, height: 1 - 0.025 * sob)
            frame[head].angle = 5 * sin(turn)
            frame[wallet].offset.height = 0.8 * sob
            frame[tail].angle = 8 * sin(turn)
            for (tear, phase) in [(tearLeft, 0.0), (tearRight, 1.6)] {
                let stretch = sin(2 * turn + phase)
                frame[tear].scale = CGSize(width: 1, height: 0.97 + 0.09 * stretch)
                frame[tear].opacity = 0.9 + 0.1 * stretch
            }
            return frame
        }
    }()

    // MARK: 发薪当天：跳起撒钱

    /// 由设计稿原图 1086×1448 拆出 7 层 (`PaydayRig`)：一跳 1.1 秒，腾空 72%，落地压扁再弹起；
    /// 双臂一里一外交替挥，头跟着歪，尾巴和领带飘带一跳甩两下，金币压在头前、跟着右手转，比身子晚半拍蹦。
    static let payday: CowRig = {
        let tail = "CowPaydayTail", armLeft = "CowPaydayArmLeft", armRight = "CowPaydayArmRight"
        let body = "CowPaydayBody", tieFlap = "CowPaydayTieFlap", head = "CowPaydayHead", coins = "CowPaydayCoins"
        let period = 1.1, airShare = 0.72, hopHeight: CGFloat = 7
        return CowRig(
            parts: [
                RigPart(image: tail, pivot: pivot(343, 1053)),
                RigPart(image: armLeft, pivot: pivot(383, 755)),
                RigPart(image: armRight, pivot: pivot(669, 755)),
                RigPart(image: body, pivot: pivot(532, 1001)),
                RigPart(image: tieFlap, pivot: pivot(551, 823)),
                RigPart(image: head, pivot: pivot(535, 733)),
                RigPart(image: coins, pivot: pivot(934, 275), follows: armRight),
            ],
            period: period
        ) { time in
            let p = time / period
            let turn = 2 * Double.pi * p
            var frame = RigFrame()
            if p < airShare {
                frame.whole.offset.height = -hopHeight * CGFloat(sin(.pi * p / airShare))
            } else {
                let squash = CGFloat(sin(.pi * (p - airShare) / (1 - airShare)))
                frame.whole.scale = CGSize(width: 1 + 0.05 * squash, height: 1 - 0.07 * squash)
            }
            frame[armLeft].angle = -14 * sin(turn)
            frame[armRight].angle = -14 * sin(turn)
            frame[head].angle = 5 * sin(turn - 0.9)
            frame[tail].angle = 18 * sin(2 * turn)
            frame[tieFlap].angle = 9 * sin(2 * turn + 1)
            frame[coins].angle = 10 * sin(2 * turn)
            frame[coins].offset.height = -5 * CGFloat(max(0, sin(turn - 0.6)))
            return frame
        }
    }()

    // MARK: 贴边探头

    /// 探头图 (`CowPeek`，右边框就是屏幕边缘) 一层，3 秒一轮：以贴边那条边为轴，第 0.6 秒放大 6% 往外一探，停一下再缩回去；
    /// 其余时间上下轻浮。不平移、不旋转，贴边那条线始终不离开屏幕边缘。贴左边时整个水平翻转 (见 `FloatingCowPeek`)。
    static let peek: CowRig = {
        let image = "CowPeek"
        let period = 3.0
        return CowRig(parts: [RigPart(image: image, pivot: UnitPoint(x: 1, y: 0.7))], period: period, shadowWidth: nil) { time in
            let out = pulse(time, start: 0.6, rise: 0.35, hold: 0.6, fall: 0.45)
            var frame = RigFrame()
            let grow = 1 + 0.06 * CGFloat(out)
            frame[image].scale = CGSize(width: grow, height: grow)
            frame[image].offset.height = CGFloat(sin(2 * .pi * time / period))
            return frame
        }
    }()

    // MARK: 动作零件

    /// 呼吸：整只以脚底为准纵向伸缩 1.5%、横向反向 0.8%，`period` 秒一次。
    private static func breath(_ time: TimeInterval, period: TimeInterval) -> RigFrame {
        let breath = sin(2 * .pi * time / period)
        var frame = RigFrame()
        frame.whole.scale = CGSize(width: 1 - 0.008 * breath, height: 1 + 0.015 * breath)
        return frame
    }

    /// 从 `start` 秒起：`rise` 秒内从 0 缓升到 1，停 `hold` 秒，再 `fall` 秒缓降回 0；其余时间为 0。
    private static func pulse(_ time: TimeInterval, start: TimeInterval, rise: TimeInterval, hold: TimeInterval, fall: TimeInterval) -> Double {
        let t = time - start
        let ease = { (x: Double) in (1 - cos(.pi * min(max(x, 0), 1))) / 2 }
        if t < 0 { return 0 }
        if t < rise { return ease(t / rise) }
        if t < rise + hold { return 1 }
        return 1 - ease((t - rise - hold) / fall)
    }

    /// 眨眼：闭眼图层在 `at` 秒起显示约 0.13 秒 (4 帧)，其余时间透明。
    private static func blinking(_ time: TimeInterval, at start: TimeInterval) -> Double {
        (start..<(start + 0.13)).contains(time) ? 1 : 0
    }

    /// 原图像素坐标归一化成关节 (所有拆层素材都是 1086×1448)。
    private static func pivot(_ x: CGFloat, _ y: CGFloat) -> UnitPoint {
        UnitPoint(x: x / 1086, y: y / 1448)
    }
}
