import Foundation
import Testing
import WageCore

// 目标达成通知与庆祝动画 (PRD 4.6.3、F9、F13)：累计中目标完成时 `advance` 产生一次达成事件，
// 事件里带好通知文案；面板下次打开时快照给出一次庆祝动画，面板播放后发命令确认。
// 与 GoalTests.swift 一样用空节假日表：2026 年 2 月按双休 20 个应出勤日，日薪 1000。

/// 09:00 新建 500 元目标「键盘」；15:00 已赚 571.4286，超过 500。
private func goalOf500() throws -> AppState {
    try creatingGoal("键盘", 500, in: try onboarded(), at: standardDay(9, 0))
}

private func applied(_ command: Command, to state: AppState, at now: Moment = standardDay(9, 0)) throws -> AppState {
    try apply(command, to: state, at: now).state
}

private let reachedNotice = DomainEvent.goalReached(message: "🎉 目标「键盘」达成")
private let celebration = GoalCelebration(goalID: 1, goalName: "键盘")

@Suite("目标达成通知")
struct GoalReachedNoticeTests {
    @Test("AC-GPRG-04 上班中累计额达到目标：推进到此刻收到【🎉 目标「键盘」达成】")
    func reachedWhileWorking() throws {
        let state = try goalOf500()

        #expect(try apply(.advance, to: state, at: standardDay(11, 0)).events.isEmpty)
        #expect(try apply(.advance, to: state, at: standardDay(15, 0)).events == [reachedNotice])
    }

    @Test("同一目标的达成通知只发一次：之后再推进不再产生")
    func onlyOnce() throws {
        let done = try apply(.advance, to: try goalOf500(), at: standardDay(15, 0)).state

        #expect(try apply(.advance, to: done, at: standardDay(15, 0, 1)).events.isEmpty)
        #expect(try apply(.advance, to: done, at: moment(2026, 2, 12, 15, 0)).events.isEmpty)
    }

    @Test("同一次推进里目标达成与下班都发生：先目标达成，再下班")
    func reachedTogetherWithOffWork() throws {
        // 09:00 新建 1000 元目标，09:30 刷新一次 (今天在等下班)；18:00 今日已赚正好 1000。
        let state = try creatingGoal("键盘", 1000, in: try onboarded(), at: standardDay(9, 0))
        let waiting = try apply(.advance, to: state, at: standardDay(9, 30)).state

        #expect(try apply(.advance, to: waiting, at: standardDay(18, 0)).events == [
            reachedNotice,
            .offWork(message: "今日 1000 元已到账，可以走了"),
        ])
    }
}

@Suite("目标达成通知：开关")
struct GoalReachedNoticeSwitchTests {
    @Test("PRD 4.7.2 目标达成通知默认开")
    func onByDefault() throws {
        #expect(snapshot(of: try onboarded(), at: standardDay(11, 0)).settings.goalReachedNotification)
        #expect(AppState().settings.goalReachedNotification)
    }

    @Test("关闭目标达成通知后不再发送；目标照常完成")
    func turnedOff() throws {
        let off = try applied(.setGoalReachedNotification(false), to: try goalOf500())
        let result = try apply(.advance, to: off, at: standardDay(15, 0))

        #expect(!result.state.settings.goalReachedNotification)
        #expect(result.events.isEmpty)
        #expect(result.state.goals.map(\.status) == [.completed(at: standardDay(15, 0).date)])
    }

    @Test("关着通知时达成的目标，之后再打开也不补发")
    func noBackfillAfterTurningOn() throws {
        let off = try applied(.setGoalReachedNotification(false), to: try goalOf500())
        let done = try apply(.advance, to: off, at: standardDay(15, 0)).state
        let on = try applied(.setGoalReachedNotification(true), to: done, at: standardDay(15, 0))

        #expect(try apply(.advance, to: on, at: standardDay(15, 1)).events.isEmpty)
    }

    @Test("下班通知与目标达成通知分别开关：只关下班通知，目标达成照发")
    func independentFromOffWork() throws {
        let state = try creatingGoal("键盘", 1000, in: try onboarded(), at: standardDay(9, 0))
        let offWorkOff = try applied(.setOffWorkNotification(false), to: state)
        let waiting = try apply(.advance, to: offWorkOff, at: standardDay(9, 30)).state

        #expect(try apply(.advance, to: waiting, at: standardDay(18, 0)).events == [reachedNotice])
    }

    @Test("PRD 4.1.2 开关属于界面设置，引导前也能改")
    func beforeOnboarding() throws {
        #expect(!(try applied(.setGoalReachedNotification(false), to: AppState()).settings.goalReachedNotification))
    }

    @Test("PRD 4.3.5 #14 #13 之前写出的设置没有目标达成通知开关，读入后为开")
    func oldSettingsFile() throws {
        let settings = try JSONDecoder().decode(InterfaceSettings.self, from: Data(#"{"offWorkNotification":false}"#.utf8))

        #expect(settings.goalReachedNotification)
        #expect(!settings.offWorkNotification)
    }
}

@Suite("目标达成：庆祝动画")
struct GoalCelebrationTests {
    @Test("动画卡片放大的目标名与通知同一句文案")
    func nameAndMessage() {
        #expect(celebration.goalName == "键盘")
        #expect(celebration.message == "🎉 目标「键盘」达成")
    }

    @Test("AC-GPRG-04 达成后打开面板播放一次庆祝动画：确认前每次取快照都有，确认后没有")
    func playsOnceAfterAcknowledged() throws {
        let done = try apply(.advance, to: try goalOf500(), at: standardDay(15, 0)).state

        #expect(snapshot(of: done, at: standardDay(15, 0)).celebration == celebration)
        #expect(snapshot(of: done, at: moment(2026, 2, 12, 9, 0)).celebration == celebration)

        let played = try applied(.acknowledgeCelebration(goalID: 1), to: done, at: standardDay(15, 1))
        #expect(snapshot(of: played, at: standardDay(15, 1)).celebration == nil)
        #expect(try apply(.advance, to: played, at: standardDay(15, 2)).state == played)
    }

    @Test("未达成时没有庆祝动画")
    func noneBeforeReached() throws {
        let state = try goalOf500()

        #expect(snapshot(of: try apply(.advance, to: state, at: standardDay(11, 0)).state, at: standardDay(11, 0)).celebration == nil)
        #expect(snapshot(of: AppState(), at: standardDay(11, 0)).celebration == nil)
    }

    @Test("关闭目标达成通知不影响庆祝动画")
    func notificationOffStillCelebrates() throws {
        let off = try applied(.setGoalReachedNotification(false), to: try goalOf500())
        let done = try apply(.advance, to: off, at: standardDay(15, 0)).state

        #expect(snapshot(of: done, at: standardDay(15, 0)).celebration == celebration)
    }

    @Test("确认的不是待播放的目标时不清掉 (如确认晚于下一个目标达成)")
    func acknowledgingOtherGoalKeepsPending() throws {
        let done = try apply(.advance, to: try goalOf500(), at: standardDay(15, 0)).state
        let other = try applied(.acknowledgeCelebration(goalID: 2), to: done, at: standardDay(15, 1))

        #expect(snapshot(of: other, at: standardDay(15, 1)).celebration == celebration)
    }

    @Test("下一个目标达成后播放它的动画")
    func nextGoalCelebrates() throws {
        let first = try apply(.advance, to: try goalOf500(), at: standardDay(15, 0)).state
        let played = try applied(.acknowledgeCelebration(goalID: 1), to: first, at: standardDay(15, 0))
        let second = try creatingGoal("耳机", 300, in: played, at: standardDay(15, 0))
        let result = try apply(.advance, to: second, at: moment(2026, 2, 12, 15, 0))

        #expect(result.events == [.goalReached(message: "🎉 目标「耳机」达成")])
        #expect(snapshot(of: result.state, at: moment(2026, 2, 12, 15, 0)).celebration
            == GoalCelebration(goalID: 2, goalName: "耳机"))
    }

    @Test("上一个目标的动画还没播放、下一个又达成：按达成先后各播放一次")
    func queuedCelebrations() throws {
        let first = try apply(.advance, to: try goalOf500(), at: standardDay(15, 0)).state
        let second = try creatingGoal("耳机", 300, in: first, at: standardDay(15, 0))
        let both = try apply(.advance, to: second, at: moment(2026, 2, 12, 15, 0)).state
        let earphones = GoalCelebration(goalID: 2, goalName: "耳机")

        #expect(snapshot(of: both, at: moment(2026, 2, 12, 15, 0)).celebration == celebration)
        let firstPlayed = try applied(.acknowledgeCelebration(goalID: 1), to: both, at: moment(2026, 2, 12, 15, 1))
        #expect(snapshot(of: firstPlayed, at: moment(2026, 2, 12, 15, 1)).celebration == earphones)
        let bothPlayed = try applied(.acknowledgeCelebration(goalID: 2), to: firstPlayed, at: moment(2026, 2, 12, 15, 1))
        #expect(snapshot(of: bothPlayed, at: moment(2026, 2, 12, 15, 1)).celebration == nil)
    }

    @Test("PRD 4.3.5 #14 没播放的动画重启后仍在，播放过的重启后不再出现")
    func survivesRestart() throws {
        let done = try apply(.advance, to: try goalOf500(), at: standardDay(15, 0)).state
        let played = try applied(.acknowledgeCelebration(goalID: 1), to: done, at: standardDay(15, 1))
        let restore = { (state: AppState) in try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state)) }

        #expect(snapshot(of: try restore(done), at: standardDay(16, 0)).celebration == celebration)
        #expect(snapshot(of: try restore(played), at: standardDay(16, 0)).celebration == nil)
    }

    @Test("PRD 4.3.5 #14 #13 之前写出的状态文件里已完成的目标不补播动画")
    func oldFileDoesNotCelebrate() throws {
        let done = try apply(.advance, to: try goalOf500(), at: standardDay(15, 0)).state
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(done)) as? [String: Any])
        json["pendingCelebrations"] = nil
        let restored = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(restored.goals == done.goals)
        #expect(snapshot(of: restored, at: standardDay(16, 0)).celebration == nil)
    }
}

/// 在 `now` 时刻依次新建若干目标 (名称、金额)，第一个累计中，其余排队。
private func queued(_ goals: [(String, Decimal)], at now: Moment = standardDay(9, 0)) throws -> AppState {
    try goals.reduce(try onboarded()) { state, goal in try creatingGoal(goal.0, goal.1, in: state, at: now) }
}

@Suite("目标达成：与目标队列 (#12) 一起")
struct GoalReachedQueueTests {
    @Test("AC-GOAL-06 因编辑目标金额而立即完成：同样发【🎉 目标「A」达成】并播放动画")
    func loweringAmountNotifies() throws {
        // 16:36 已赚 800，把 A 从 1000 改成 500。
        let state = try queued([("A", 1000), ("B", 3000)])
        let result = try apply(.editGoal(id: 1, name: "A", amount: 500), to: state, at: standardDay(16, 36))

        #expect(result.events == [.goalReached(message: "🎉 目标「A」达成")])
        #expect(snapshot(of: result.state, at: standardDay(16, 36)).celebration
            == GoalCelebration(goalID: 1, goalName: "A"))
        #expect(try apply(.advance, to: result.state, at: standardDay(16, 37)).events.isEmpty)
    }

    @Test("D5 删除累计中 A 后 B 继承的累计额已达标：B 立即完成，发一条达成通知")
    func inheritedCompletionNotifies() throws {
        let state = try queued([("A", 1000), ("B", 200), ("C", 3000)])
        let result = try apply(.deleteGoal(id: 1), to: state, at: standardDay(13, 6))

        #expect(result.events == [.goalReached(message: "🎉 目标「B」达成")])
        #expect(snapshot(of: result.state, at: standardDay(13, 6)).celebration?.goalID == 2)
    }

    @Test("零头结转后连续完成 A、B：各发一条通知，动画按完成先后各播放一次")
    func chainedCompletionsEachCelebrate() throws {
        // 18:00 今日已赚 1000：A 500、B 300 都完成，C 带着 200 开始。
        let state = try queued([("A", 500), ("B", 300), ("C", 3000)])
        let result = try apply(.advance, to: state, at: standardDay(18, 0))
        let celebration = { (state: AppState) in snapshot(of: state, at: standardDay(18, 0)).celebration }

        #expect(result.events.filter { if case .goalReached = $0 { true } else { false } } == [
            .goalReached(message: "🎉 目标「A」达成"),
            .goalReached(message: "🎉 目标「B」达成"),
        ])
        #expect(celebration(result.state) == GoalCelebration(goalID: 1, goalName: "A"))
        let aPlayed = try applied(.acknowledgeCelebration(goalID: 1), to: result.state, at: standardDay(18, 0))
        #expect(celebration(aPlayed) == GoalCelebration(goalID: 2, goalName: "B"))
        let bothPlayed = try applied(.acknowledgeCelebration(goalID: 2), to: aPlayed, at: standardDay(18, 0))
        #expect(celebration(bothPlayed) == nil)
    }

    @Test("关闭目标达成通知时连续完成：一条都不发，动画照常排队")
    func chainedCompletionsWithNotificationOff() throws {
        let state = try applied(.setGoalReachedNotification(false), to: try queued([("A", 500), ("B", 300), ("C", 3000)]))
        let result = try apply(.advance, to: state, at: standardDay(17, 59))

        #expect(result.events.isEmpty)
        #expect(snapshot(of: result.state, at: standardDay(17, 59)).celebration?.goalID == 1)
    }

    @Test("待播放的目标在播放前被删掉：跳过它，播放下一个")
    func deletedBeforePlaying() throws {
        let state = try apply(.advance, to: try queued([("A", 500), ("B", 300), ("C", 3000)]), at: standardDay(18, 0)).state
        let deleted = try applied(.deleteGoal(id: 1), to: state, at: standardDay(18, 1))

        #expect(snapshot(of: deleted, at: standardDay(18, 1)).celebration?.goalID == 2)
    }
}
