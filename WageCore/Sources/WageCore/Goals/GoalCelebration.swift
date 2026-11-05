import Foundation

/// 面板该播放的目标达成庆祝动画 (PRD F9、AC-GPRG-04)，只播放一次。
/// 外壳在面板上播放后发 `.acknowledgeCelebration(goalID:)`，之后的快照里就没有了。
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
    /// 待播放的目标还在且已完成时才播放；该目标后来被删掉了就不播放。
    init?(state: AppState) {
        guard let id = state.pendingCelebration,
              let goal = state.goals.first(where: { $0.id == id }),
              case .completed = goal.status else { return nil }
        self.init(goalID: id, message: NotificationCopy.goalReached(name: goal.name))
    }
}
