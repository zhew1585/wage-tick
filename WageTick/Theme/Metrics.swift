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
    static let r18: CGFloat = 18

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
    // 760 设计稿补的：日历行距 5、单日详情结算区上边距 26。
    static let s5: CGFloat = 5
    static let s26: CGFloat = 26

    /// 面板、表单页左右内边距。
    static let screen = s20
    /// 子页面 (目标、历史、设置) 的宽度，设计稿 P3 至 P6 都是 360。
    static let pageWidth = WindowMetrics.size.width
}

/// 所有窗口 (引导、今日概览；目标、历史、设置在今日概览窗口里) 统一的固定内容尺寸，不能拉伸：
/// 宽 360 (设计稿各屏同宽)；高 574，是首页七个区域叠起来正好的高度 (见 `HomeLayout`，Allen 定)。
/// 放不下的 (目标多了、历史月份多了、设置页、单日详情) 在窗口里滚动中间内容区，页头和底部按钮栏不动 (`ScrollBody`)。
/// 弹出的 sheet (改月薪、补记等小表单) 不在此列，仍按内容大小。
enum WindowMetrics {
    static let size = CGSize(width: 360, height: 574)
}

/// 今日概览首页七个区域的上沿与高度 (相对窗口左上角，含标题栏)。所有状态下都一样，换状态只换区域里的内容，不挪位置。
/// 块间距：日期行到主数字区 24，主数字区到进度区 16，其余 12。各区域叠到底正好是 `WindowMetrics.size.height`。
enum HomeLayout {
    /// 日期与状态行。
    static let topBar = Band(top: 40, height: 24)
    /// 主数字区：小标题、主数字、说明行。休息日时与进度区合成一整块放小牛和「今天休息」。
    static let hero = Band(top: 88, height: 108)
    /// 进度区：「已工作」或「最多白干」行、分段条、两端时间；已下班换成「我还没走」按钮，上下留白居中。
    static let progress = Band(top: 212, height: 56)
    /// 统计卡。
    static let stats = Band(top: 280, height: 64)
    /// 攒钱队列：不滑动，最多显示 3 个目标。
    static let goals = Band(top: 356, height: 104)
    /// 情绪按钮。
    static let actions = Band(top: 472, height: 44)
    /// 底部入口栏。
    static let footer = Band(top: 528, height: 46)

    /// 一个区域：上沿与高度。
    struct Band {
        let top: CGFloat
        let height: CGFloat
        var bottom: CGFloat { top + height }
    }
}

/// 首页提示条的位置 (相对窗口左上角)：和红绿灯、图钉同一行，左边让出红绿灯 (原版标题的起点 85)，右边离图钉 7。
/// 只占一行，放不下时横向滚动 (`PanelNoticeBanner`)。
enum HomeNoticeLayout {
    static let frame = CGRect(x: 85, y: 14, width: 236, height: 24)
}

/// 控件高度 token (设计稿里直接写的高度)。
enum ControlHeight {
    /// 子页面底部整宽主按钮 (目标页「新目标」)，760 设计稿 44。
    static let footerButton: CGFloat = 44
    /// 设置页「清空数据并重启」整宽按钮，760 设计稿 40。
    static let wideButton: CGFloat = 40
}
