import Foundation

/// 面板该播放的目标达成庆祝动画 (PRD F9、AC-GPRG-04)，每个目标只播放一次。
/// 外壳在面板上开始播放时发 `.acknowledgeCelebration(goalID:)`，之后的快照里就没有它了；
/// 还有别的目标在等时，下一次快照给出下一个。
public struct GoalCelebration: Sendable, Equatable {
    /// 达成的目标编号，确认时原样带回。
    public let goalID: Int
    /// 动画里的文字，与达成通知同一句，如「🎉 目标「Switch 2」达成」。
    public let message: String

    public init(goalID: Int, message: String) {
        self.goalID = goalID
        self.message = message
    }
}

extension GoalCelebration {
    /// 待播放里按达成先后取第一个仍在且已完成的目标；后来被删掉的跳过。
    init?(state: AppState) {
        let completed = state.goals.filter(\.status.isCompleted)
        guard let goal = state.pendingCelebrations.lazy.compactMap({ id in completed.first { $0.id == id } }).first else {
            return nil
        }
        self.init(goalID: goal.id, message: NotificationCopy.goalReached(name: goal.name))
    }
}

/// 面板开始播放 `goalID` 的庆祝动画时确认，之后不再播放；其余待播放的不受影响。
/// 排进待播放在 `completingReachedGoals` (目标完成的唯一入口)。
func acknowledgeCelebration(goalID: Int, state: AppState) -> AppState {
    var next = state
    next.pendingCelebrations = state.pendingCelebrations.filter { $0 != goalID }
    return next
}
