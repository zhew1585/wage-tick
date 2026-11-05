import CoreGraphics

/// 圆角 token。名字里的数字就是设计稿里的 pt 值，另有几个按用途起名的别名。
enum Radius {
    static let r2: CGFloat = 2
    static let r4: CGFloat = 4
    static let r5: CGFloat = 5
    static let r6: CGFloat = 6
    static let r7: CGFloat = 7
    static let r8: CGFloat = 8
    static let r9: CGFloat = 9
    static let r10: CGFloat = 10
    static let r12: CGFloat = 12
    static let r14: CGFloat = 14
    static let r16: CGFloat = 16

    /// 按钮、输入框、日历格子。
    static let control = r8
    /// 卡片 (目标卡、月份卡等)。
    static let card = r12
}

/// 间距 token (gap、padding)。名字里的数字就是设计稿里的 pt 值。
enum Spacing {
    static let s1: CGFloat = 1
    static let s2: CGFloat = 2
    static let s3: CGFloat = 3
    static let s4: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s10: CGFloat = 10
    static let s12: CGFloat = 12
    static let s14: CGFloat = 14
    static let s16: CGFloat = 16
    static let s18: CGFloat = 18
    static let s20: CGFloat = 20
    static let s22: CGFloat = 22
    static let s24: CGFloat = 24

    /// 面板、表单页左右内边距。
    static let screen = s20
    /// 子页面 (目标、历史、设置) 的宽度，设计稿 P3 至 P6 都是 360。
    static let pageWidth = WindowMetrics.size.width
}

/// 所有窗口 (引导、今日概览、目标、历史、设置) 统一的固定内容尺寸，不能拉伸：
/// 宽 360 (设计稿各屏同宽)；高 760，接近手机的比例 (Allen 定)，设计稿各屏都放得下，放不下的在窗口里滚动。
/// 放不下的 (目标多了、设置页、展开排队目标的面板) 在窗口里滚动中间内容区，页头和底部按钮栏不动 (`ScrollBody`)。
/// 弹出的 sheet (改月薪、补记等小表单) 不在此列，仍按内容大小。
enum WindowMetrics {
    static let size = CGSize(width: 360, height: 760)
}
