import Foundation

/// 某一时刻的完整推导结果，外壳只按它展示，不做任何业务计算。
public struct Snapshot: Sendable, Equatable {
    /// 菜单栏应显示的内容，外壳原样展示，不得自行拼接文字或货币符号。
    public let menuBar: MenuBarDisplay
    /// 今天的推导结果；未完成引导时为 nil。
    public let today: Today?
    /// 今日概览面板的展示内容；未完成引导时为 nil。
    public let panel: TodayPanel?
}

/// 菜单栏内容：小牛姿势 + 可选数字 (PRD 4.7.1 第 1、2 条)。
public struct MenuBarDisplay: Sendable, Equatable {
    public let pose: CowPose
    /// 只含数字和小数点，nil 时只显示小牛。
    public let text: String?

    public init(pose: CowPose, text: String?) {
        self.pose = pose
        self.text = text
    }
}

/// 菜单栏小牛的姿势，与日状态一一对应 (PRD 4.3.3 主状态概览)。
public enum CowPose: Sendable, Equatable {
    case sunbathing  // 晒太阳：休息日
    case yawning     // 打哈欠：未上班，也用于未完成引导
    case grinding    // 埋头拉磨：上班中
    case sleeping    // 趴着睡：午休中
    case lyingFlat   // 躺平：已下班
}

/// 核心入口二：推导 `state` 在 `now` 时刻的快照，纯函数，不改状态。
public func snapshot(of state: AppState, at now: Moment) -> Snapshot {
    guard let profile = state.profile else {
        return Snapshot(menuBar: MenuBarDisplay(pose: .yawning, text: nil), today: nil, panel: nil)
    }
    let today = Today(profile: profile, now: now)
    return Snapshot(
        menuBar: MenuBarDisplay(today: today),
        today: today,
        panel: TodayPanel(today: today, profile: profile, now: now)
    )
}
