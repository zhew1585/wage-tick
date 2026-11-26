import Foundation
import Testing
import WageCore

// 目标金额上限与预计完成的天数上限：金额再大、日薪再小，快照都立即生成，不卡死、不崩。
// 除特别说明外与 GoalTests 同一约定：2026-02-11 (周三)，空节假日表，月薪 20000 时日薪 1000。

/// 在 `now` 时刻执行一条命令，返回新状态。
private func applying(_ command: Command, to state: AppState, at now: Moment) throws -> AppState {
    try apply(command, to: state, at: now).state
}

/// 执行命令应被拒绝时的错误；没被拒绝时测试失败。
private func rejection(_ command: Command, to state: AppState, at now: Moment) -> CommandError? {
    do {
        _ = try apply(command, to: state, at: now)
        Issue.record("期望被拒绝，实际执行成功")
        return nil
    } catch {
        return error
    }
}

@Suite("目标金额上限")
struct GoalAmountLimitValidationTests {
    @Test("新建目标金额 999999 可以存")
    func limitIsAllowed() throws {
        let state = try applying(.createGoal(name: "房子首付", amount: 999999), to: try onboarded(), at: standardDay(9, 0))

        #expect(state.goals.map(\.amount) == [999999])
    }

    @Test("新建目标金额超过 999999 被拒绝，提示「金额最多 999999」", arguments: [Decimal(string: "999999.01")!, 1000000])
    func overLimitIsRejected(amount: Decimal) throws {
        let error = rejection(.createGoal(name: "房子首付", amount: amount), to: try onboarded(), at: standardDay(9, 0))

        #expect(error == .goalAmountTooLarge)
        #expect(error?.message == "金额最多 999999")
    }

    @Test("编辑目标同样最多 999999")
    func editIsLimited() throws {
        let state = try applying(.createGoal(name: "键盘", amount: 500), to: try onboarded(), at: standardDay(9, 0))
        let id = try #require(state.goals.first).id

        #expect(rejection(.editGoal(id: id, name: "键盘", amount: 1000000), to: state, at: standardDay(9, 0)) == .goalAmountTooLarge)
        let edited = try applying(.editGoal(id: id, name: "键盘", amount: 999999), to: state, at: standardDay(9, 0))
        #expect(edited.goals.map(\.amount) == [999999])
    }

    @Test("名称为空或金额不大于 0 仍是原来的提示")
    func otherInvalidGoalsKeepMessage() throws {
        let state = try onboarded()

        #expect(rejection(.createGoal(name: " ", amount: 500), to: state, at: standardDay(9, 0)) == .invalidGoal)
        #expect(rejection(.createGoal(name: "键盘", amount: 0), to: state, at: standardDay(9, 0)) == .invalidGoal)
    }
}

/// 2026-02-11 09:00 按日薪 `wage` 完成引导后的状态 (只按双休)。
private func onboardedDaily(_ wage: Decimal) throws -> AppState {
    let input = OnboardingInput(salary: wage, payBasis: .daily, schedule: standardSchedule)
    return try apply(.completeOnboarding(input), to: AppState(), at: standardDay(9, 0)).state
}

/// 把状态存成 JSON，所有目标的金额改成 `amount` 后读回，模拟上限出现之前存下的数据。
private func storing(_ state: AppState, goalAmount amount: String) throws -> AppState {
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    let goals = try #require(json["goals"] as? [[String: Any]])
    json["goals"] = goals.map { goal in goal.merging(["amount": amount]) { $1 } }
    return try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
}

@Suite("预计完成的天数上限", .timeLimit(.minutes(1)))
struct GoalEstimateLimitTests {
    @Test("已存的 1e30 元目标照常读入，快照立即生成：只说还需多少天，不数日期")
    func storedHugeGoal() throws {
        let created = try applying(.createGoal(name: "A", amount: 500), to: try onboarded(), at: standardDay(9, 0))
        let state = try storing(applying(.createGoal(name: "B", amount: 500), to: created, at: standardDay(9, 0)), goalAmount: "1e30")

        #expect(state.goals.map(\.amount) == [Decimal(string: "1e30")!, Decimal(string: "1e30")!])
        // 9:00 还没上班，先扣今天能赚的 1000：(1e30 - 1000) ÷ 1000 = 1e27 - 1 天。
        let days = "999999999999999999999999999"
        let active = try activeGoal(state, at: standardDay(9, 0))
        #expect(active.estimate == "还需搬砖 \(days) 天")
        #expect(active.shortEstimate == "还需 \(days) 天")
        #expect(active.finishText == nil)

        let list = try #require(snapshot(of: state, at: standardDay(9, 0)).goals)
        #expect(list.queue.map(\.asFirst.estimate) == ["还需搬砖 \(days) 天", "还需搬砖 \(days) 天"])
        #expect(list.queue.map(\.estimate) == ["还需搬砖 \(days) 天", "排队中 · 暂时没法预计"])
        #expect(list.queueFinishText == nil)
    }

    @Test("日薪 0.01 时 999999 元的目标立即算出天数")
    func tinyDailyWage() throws {
        let state = try applying(.createGoal(name: "房子首付", amount: 999999), to: try onboardedDaily(Decimal(string: "0.01")!), at: standardDay(9, 0))

        // 先扣今天能赚的 0.01：999998.99 ÷ 0.01 = 99999899 天。
        let active = try activeGoal(state, at: standardDay(9, 0))
        #expect(active.estimate == "还需搬砖 99999899 天")
        #expect(active.shortEstimate == "还需 99999899 天")
        #expect(active.finishText == nil)
        #expect(try #require(snapshot(of: state, at: standardDay(9, 0)).goals).queue.map(\.asFirst.shortEstimate) == ["还需 99999899 天"])
    }

    @Test("刚好 10000 个应出勤日照常带日期，10001 个只说天数")
    func boundary() throws {
        // 日薪 10，下班后新建：累计额 0，今天不再扣。
        let onboarded = try onboardedDaily(10)
        let within = try applying(.createGoal(name: "A", amount: 100000), to: onboarded, at: standardDay(18, 0))
        let beyond = try applying(.createGoal(name: "A", amount: 100010), to: onboarded, at: standardDay(18, 0))

        // 只按双休，10000 个应出勤日正好 2000 周：2026-02-11 (周三) 之后 14000 天，2064-06-11 (周三)。
        let near = try activeGoal(within, at: standardDay(18, 0))
        #expect(near.estimate == "还需搬砖 10000 天 · 6月11日")
        #expect(near.finishText == "2064年6月")

        let far = try activeGoal(beyond, at: standardDay(18, 0))
        #expect(far.estimate == "还需搬砖 10001 天")
        #expect(far.shortEstimate == "还需 10001 天")
        #expect(far.finishText == nil)
    }

    @Test("排队中目标自己超过 10000 个应出勤日时不数日期")
    func queuedBeyondLimit() throws {
        let first = try applying(.createGoal(name: "A", amount: 100), to: try onboardedDaily(10), at: standardDay(18, 0))
        let state = try applying(.createGoal(name: "B", amount: 999999), to: first, at: standardDay(18, 0))

        let list = try #require(snapshot(of: state, at: standardDay(18, 0)).goals)
        #expect(list.queue.map(\.estimate) == ["还需搬砖 10 天 · 2月25日", "排队中 · 暂时没法预计"])
    }
}
