import Foundation

/// 某一时刻的完整推导结果，外壳只按它展示，不做任何业务计算。
public struct Snapshot: Sendable, Equatable {
    /// 菜单栏应显示的内容，外壳原样展示，不得自行拼接文字或货币符号。
    public let menuBar: MenuBarDisplay
    /// 今天的推导结果；未完成引导时为 nil。
    public let today: Today?
    /// 界面设置原样带出，供外壳展示菜单勾选与快捷键。
    public let settings: InterfaceSettings
    /// 今日概览面板的展示内容；未完成引导时为 nil。
    public let panel: TodayPanel?
    /// 设置页的初始值；未完成引导时为 nil。
    public let settingsForm: SettingsForm?
    /// 请假表单 (F6) 的内容；未完成引导或今天不应出勤时为 nil，此时没有请假入口 (PRD 4.3.5 #8)。
    public let leaveForm: LeaveForm?
    /// 目标管理页的目标列表 (PRD F8)；未完成引导时为 nil。
    public let goals: [GoalRow]?
    /// 面板该播放的目标达成庆祝动画 (PRD F9)，播放后发 `.acknowledgeCelebration` 确认；没有时为 nil。
    public let celebration: GoalCelebration?
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

/// 菜单栏小牛的姿势，与日状态一一对应 (PRD 4.3.3 主状态概览)；白干计时中另有冒汗姿势。
public enum CowPose: Sendable, Equatable {
    case sunbathing  // 晒太阳：休息日
    case yawning     // 打哈欠：未上班，也用于未完成引导
    case grinding    // 埋头拉磨：上班中
    case sleeping    // 趴着睡：午休中
    case lyingFlat   // 躺平：已下班
    case sweating    // 边拉磨边冒汗：白干计时中，不论日状态
}

/// 核心入口二：推导 `state` 在 `now` 时刻的快照，纯函数，不改状态。
/// `holidays` 由节假日数据源适配器提供；不传时为空表，只按双休判定应出勤日。
/// 换上新的节假日表重新取快照，当月日薪与结算随之重算 (PRD 4.3.5 #16)。
public func snapshot(of state: AppState, at now: Moment, holidays: HolidayTable = .empty) -> Snapshot {
    guard let profile = state.profile else {
        return Snapshot(
            menuBar: MenuBarDisplay(pose: .yawning, text: nil), today: nil, settings: state.settings, panel: nil,
            settingsForm: nil, leaveForm: nil, goals: nil, celebration: nil
        )
    }
    let today = Today(profile: profile, dayRecords: state.dayRecords, now: now, holidays: holidays)
    let activeGoal = ActiveGoalCard(state: state, profile: profile, today: today, holidays: holidays)
    return Snapshot(
        menuBar: MenuBarDisplay(today: today, settings: state.settings),
        today: today,
        settings: state.settings,
        panel: TodayPanel(today: today, now: now, holidays: holidays, goal: GoalCard(active: activeGoal)),
        settingsForm: SettingsForm(profile: profile, today: today.date),
        leaveForm: LeaveForm(today: today, now: now),
        goals: GoalRow.rows(state: state, active: activeGoal, today: today, now: now),
        celebration: GoalCelebration(state: state)
    )
}
