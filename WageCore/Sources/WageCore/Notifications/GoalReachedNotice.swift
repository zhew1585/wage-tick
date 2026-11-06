import Foundation

// 目标达成通知 (PRD 4.6.3、F13)：事件由 `completingReachedGoals` 产生，这里放文案与开关。

extension NotificationCopy {
    /// 目标达成通知正文，如「🎉 目标「Switch 2」达成」。不含金额 (PRD 4.6.3)。
    /// 面板庆祝动画里的文字也用这一句。
    static func goalReached(name: String) -> String {
        "🎉 目标「\(name)」达成"
    }
}

/// 目标达成通知开关属于界面设置，引导前也能改。关掉只是不发通知，目标照常完成、面板照常播放庆祝动画。
func setGoalReachedNotification(_ enabled: Bool, state: AppState) -> AppState {
    var next = state
    next.settings.goalReachedNotification = enabled
    return next
}
