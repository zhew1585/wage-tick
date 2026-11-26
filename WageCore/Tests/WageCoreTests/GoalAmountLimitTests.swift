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

@Suite("预计完成最多看一年", .timeLimit(.minutes(1)))
struct GoalEstimateLimitTests {
    @Test("已存的 1e30 元目标照常读入，快照立即生成：只说大于 1 年，不数日期")
    func storedHugeGoal() throws {
        let created = try applying(.createGoal(name: "A", amount: 500), to: try onboarded(), at: standardDay(9, 0))
        let state = try storing(applying(.createGoal(name: "B", amount: 500), to: created, at: standardDay(9, 0)), goalAmount: "1e30")

        #expect(state.goals.map(\.amount) == [Decimal(string: "1e30")!, Decimal(string: "1e30")!])
        let active = try activeGoal(state, at: standardDay(9, 0))
        #expect(active.estimate == "还需搬砖大于 1 年")
        #expect(active.shortEstimate == "还需大于 1 年")
        #expect(active.finishText == "大于 1 年")

        let list = try #require(snapshot(of: state, at: standardDay(9, 0)).goals)
        #expect(list.queue.map(\.asFirst.estimate) == ["还需搬砖大于 1 年", "还需搬砖大于 1 年"])
        #expect(list.queue.map(\.estimate) == ["还需搬砖大于 1 年", "排队中 · 大于 1 年"])
        #expect(list.queueFinishText == nil)
    }

    // 十进制能存的最大金额，÷ 日薪 0.01 时溢出，算不出天数。
    @Test("金额大到十进制也算不出天数时同样是大于 1 年")
    func daysOverflowDecimal() throws {
        let state = try storing(applying(.createGoal(name: "A", amount: 500), to: try onboardedDaily(Decimal(string: "0.01")!), at: standardDay(9, 0)), goalAmount: "340282366920938463463374607431768211455e127")

        let active = try activeGoal(state, at: standardDay(9, 0))
        #expect(active.estimate == "还需搬砖大于 1 年")
        #expect(active.shortEstimate == "还需大于 1 年")
        #expect(active.finishText == "大于 1 年")
    }

    @Test("日薪 0.01 时 999999 元的目标立即给出预计：大于 1 年")
    func tinyDailyWage() throws {
        let state = try applying(.createGoal(name: "房子首付", amount: 999999), to: try onboardedDaily(Decimal(string: "0.01")!), at: standardDay(9, 0))

        let active = try activeGoal(state, at: standardDay(9, 0))
        #expect(active.estimate == "还需搬砖大于 1 年")
        #expect(active.shortEstimate == "还需大于 1 年")
        #expect(active.finishText == "大于 1 年")
        #expect(try #require(snapshot(of: state, at: standardDay(9, 0)).goals).queue.map(\.asFirst.shortEstimate) == ["还需大于 1 年"])
    }

    @Test("预计完成日正好是今天之后第 365 天时照常带天数和日期，第 366 天起说大于 1 年")
    func boundary() throws {
        // 日薪 10，下班后新建：累计额 0，今天不再扣。
        let onboarded = try onboardedDaily(10)
        let within = try applying(.createGoal(name: "A", amount: 2610), to: onboarded, at: standardDay(18, 0))
        let beyond = try applying(.createGoal(name: "A", amount: 2620), to: onboarded, at: standardDay(18, 0))

        // 只按双休，2026-02-12 至 2027-02-11 (今天之后第 365 天，周四) 是 52 周加 1 天，共 261 个应出勤日；
        // 第 262 个是 2027-02-12 (周五)，今天之后第 366 天。
        let near = try activeGoal(within, at: standardDay(18, 0))
        #expect(near.estimate == "还需搬砖 261 天 · 2月11日")
        #expect(near.shortEstimate == "还需 261 天 · 2月11日")
        #expect(near.finishText == "2027年2月")

        let far = try activeGoal(beyond, at: standardDay(18, 0))
        #expect(far.estimate == "还需搬砖大于 1 年")
        #expect(far.shortEstimate == "还需大于 1 年")
        #expect(far.finishText == "大于 1 年")
    }

    @Test("排队中目标自己就超过一年时说大于 1 年")
    func queuedBeyondLimit() throws {
        let first = try applying(.createGoal(name: "A", amount: 100), to: try onboardedDaily(10), at: standardDay(18, 0))
        let state = try applying(.createGoal(name: "B", amount: 999999), to: first, at: standardDay(18, 0))

        let snap = snapshot(of: state, at: standardDay(18, 0))
        #expect(try #require(snap.goals).queue.map(\.estimate) == ["还需搬砖 10 天 · 2月25日", "排队中 · 大于 1 年"])
        let queued = try #require(snap.panel?.goalQueue?.upcoming.first)
        #expect(queued.estimate == "排队中 · 大于 1 年")
        #expect(queued.shortEstimate == "大于 1 年")
        #expect(queued.finishText == "大于 1 年")
    }

    @Test("排在已经超过一年的目标后面时同样是大于 1 年")
    func queuedBehindFarGoal() throws {
        let first = try applying(.createGoal(name: "A", amount: 2620), to: try onboardedDaily(10), at: standardDay(18, 0))
        let state = try applying(.createGoal(name: "B", amount: 100), to: first, at: standardDay(18, 0))

        let snap = snapshot(of: state, at: standardDay(18, 0))
        #expect(try #require(snap.goals).queue.map(\.estimate) == ["还需搬砖大于 1 年", "排队中 · 大于 1 年"])
        let queued = try #require(snap.panel?.goalQueue?.upcoming.first)
        #expect(queued.shortEstimate == "大于 1 年")
        #expect(queued.finishText == "大于 1 年")
    }

    @Test("排队中目标的一年也从今天算：前一个不远，累加后超过今天之后 365 天就是大于 1 年")
    func queuedLimitCountsFromToday() throws {
        // 日薪 10：A 要 200 个应出勤日，B 自己只要 61 个 (不到一年)，接在 A 后面共 261 个正好第 365 天，C 再要 1 个就超了。
        var state = try applying(.createGoal(name: "A", amount: 2000), to: try onboardedDaily(10), at: standardDay(18, 0))
        state = try applying(.createGoal(name: "B", amount: 610), to: state, at: standardDay(18, 0))
        state = try applying(.createGoal(name: "C", amount: 10), to: state, at: standardDay(18, 0))

        let snap = snapshot(of: state, at: standardDay(18, 0))
        let estimates = try #require(snap.goals).queue.map(\.estimate)
        #expect(estimates.dropFirst() == ["排队中 · 预计 2027年2月", "排队中 · 大于 1 年"])
        #expect(snap.panel?.goalQueue?.upcoming.map(\.finishText) == ["2027年2月", "大于 1 年"])
    }

    @Test("日薪为 0 时仍是「暂时没法预计」，不说大于 1 年")
    func zeroDailyWageKeepsNoEstimate() throws {
        let first = try applying(.createGoal(name: "A", amount: 100), to: try onboardedDaily(10), at: standardDay(18, 0))
        let created = try applying(.createGoal(name: "B", amount: 100), to: first, at: standardDay(18, 0))
        // 本月工作日全部覆盖为不上班：当月应出勤日为 0，日薪为 0。
        var state = created
        for day in 1...28 where !LocalDate(year: 2026, month: 2, day: day).isSaturdayOrSunday {
            state = try applying(.editDay(LocalDate(year: 2026, month: 2, day: day), .setOverride(.dayOff)), to: state, at: standardDay(18, 0))
        }

        let snap = snapshot(of: state, at: standardDay(18, 0))
        let active = try activeGoal(state, at: standardDay(18, 0))
        #expect(active.estimate == "本月没有要上班的日子，暂时没法预计")
        #expect(active.shortEstimate == "暂时没法预计")
        #expect(active.finishText == nil)
        #expect(try #require(snap.goals).queue.map(\.estimate) == ["本月没有要上班的日子，暂时没法预计", "排队中 · 暂时没法预计"])
        let queued = try #require(snap.panel?.goalQueue?.upcoming.first)
        #expect(queued.shortEstimate == "暂时没法预计")
        #expect(queued.finishText == nil)
    }
}
