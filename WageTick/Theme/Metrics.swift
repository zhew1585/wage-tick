import CoreGraphics

/// 圆角 token。名字里的数字就是设计稿里的 pt 值，另有几个按用途起名的别名。
enum Radius {
    static let r4: CGFloat = 4
    static let r6: CGFloat = 6
    static let r8: CGFloat = 8
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
    static let s2: CGFloat = 2
    static let s4: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s10: CGFloat = 10
    static let s12: CGFloat = 12
    static let s14: CGFloat = 14
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24

    /// 面板、表单页左右内边距。
    static let screen = s20
}
