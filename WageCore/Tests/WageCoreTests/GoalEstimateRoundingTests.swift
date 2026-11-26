import Foundation
import Testing
import WageCore

// 预计完成的天数不会是 0：剩余金额只剩十进制除法的末位误差时今天就能达成；排队中目标金额再小也至少数 1 个应出勤日。
// 空节假日表 (只按双休)。

/// 在 `now` 时刻按日薪 `wage` 完成引导后的状态 (只按双休)。
private func onboardedDaily(_ wage: Decimal, at now: Moment = standardDay(9, 0)) throws -> AppState {
    let input = OnboardingInput(salary: wage, payBasis: .daily, schedule: standardSchedule)
    return try apply(.completeOnboarding(input), to: AppState(), at: now).state
}

@Suite("预计完成不会是 0 天")
struct GoalEstimateRoundingTests {
    @Test("月薪 20000、当月 21 个应出勤日：月初定 20000 的目标，第 21 个应出勤日下班后今天就能达成，不说还需 0 天")
    func truncatedDailyWageRemainder() throws {
        // 2026 年 5 月只按双休有 21 个应出勤日，日薪 20000 ÷ 21 在十进制末位被截断；5 月 29 日 (周五) 是第 21 个。
        let start = moment(2026, 5, 1, 9, 0)
        let state = try creatingGoal("年终旅行", 20000, in: try onboarded(at: start), at: start)
        let evening = moment(2026, 5, 29, 18, 30)

        let active = try activeGoal(state, at: evening)
        #expect(active.estimate == "今天就能达成")
        #expect(active.shortEstimate == "今天就能达成")
        #expect(active.finishText == "今天")
    }

    @Test("排队中目标相对日薪极小时也至少数 1 个应出勤日，不和前一个同一天")
    func tinyQueuedGoalCountsOneDay() throws {
        // 日薪 1000000000，下班后：A 要 1 个应出勤日 (2月12日 周四)，B 只要 0.01，排在 A 之后的下一个应出勤日 2月13日 (周五)。
        let first = try creatingGoal("A", 100, in: try onboardedDaily(1_000_000_000), at: standardDay(18, 0))
        let state = try creatingGoal("B", Decimal(string: "0.01")!, in: first, at: standardDay(18, 0))

        let snap = snapshot(of: state, at: standardDay(18, 0))
        #expect(try #require(snap.goals).queue.map(\.estimate) == ["还需搬砖 1 天 · 2月12日", "排队中 · 预计 2月13日"])
        #expect(snap.panel?.goalQueue?.upcoming.map(\.finishText) == ["2月13日"])
    }

    @Test("前一个目标落在周五时，极小的排队中目标数到下周一的应出勤日，不落在周末")
    func tinyQueuedGoalSkipsWeekend() throws {
        // 2月12日 (周四) 下班后、日薪 1000000000：A 要 1 个应出勤日 (2月13日 周五)，
        // B、C 都只要 0.01，依次落在下周一 2月16日、下周二 2月17日。
        let evening = moment(2026, 2, 12, 18, 0)
        var state = try onboardedDaily(1_000_000_000, at: moment(2026, 2, 12, 9, 0))
        state = try creatingGoal("A", 100, in: state, at: evening)
        state = try creatingGoal("B", Decimal(string: "0.01")!, in: state, at: evening)
        state = try creatingGoal("C", Decimal(string: "0.01")!, in: state, at: evening)

        let snap = snapshot(of: state, at: evening)
        #expect(try #require(snap.goals).queue.map(\.estimate)
            == ["还需搬砖 1 天 · 2月13日", "排队中 · 预计 2月16日", "排队中 · 预计 2月17日"])
    }

    @Test("累计中目标相对日薪极小时，下班后同样是今天就能达成")
    func tinyActiveGoalAfterWork() throws {
        let state = try creatingGoal("A", Decimal(string: "0.01")!, in: try onboardedDaily(1_000_000_000), at: standardDay(18, 0))

        let active = try activeGoal(state, at: standardDay(18, 0))
        #expect(active.estimate == "今天就能达成")
        #expect(active.finishText == "今天")
    }
}

@Suite("已完成目标折合搬砖天数")
struct CompletedWorkDaysOverflowTests {
    @Test("金额大到十进制算不出天数时不显示折合天数，不拼出 NaN")
    func overflowShowsNoWorkDays() throws {
        // 日薪 0.01：9:00 新建 0.01 的目标，当天下班前已达成。
        let created = try creatingGoal("A", Decimal(string: "0.01")!, in: try onboardedDaily(Decimal(string: "0.01")!), at: standardDay(9, 0))
        let done = try apply(.advance, to: created, at: standardDay(18, 0)).state
        #expect(try #require(snapshot(of: done, at: standardDay(18, 0)).goals).completed.count == 1)

        // 上限出现之前存下的超大金额：÷ 日薪 0.01 时十进制溢出。
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(done)) as? [String: Any])
        let goals = try #require(json["goals"] as? [[String: Any]])
        json["goals"] = goals.map { $0.merging(["amount": "340282366920938463463374607431768211455e127"]) { $1 } }
        let state = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))

        let list = try #require(snapshot(of: state, at: standardDay(18, 0)).goals)
        #expect(list.completed.map(\.workDaysText) == [nil])
        #expect(list.completedSummary?.contains("NaN") == false)
        #expect(list.completedSummary?.contains("搬砖") == false)
    }
}
