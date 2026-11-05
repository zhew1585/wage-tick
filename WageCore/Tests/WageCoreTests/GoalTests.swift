import Foundation
import Testing
import WageCore

/// 面板目标区；未完成引导时测试失败。
func goalCard(_ state: AppState, at now: Moment) throws -> GoalCard {
    try #require(snapshot(of: state, at: now).panel).goal
}

/// 面板目标区里的累计中目标；队列为空时测试失败。
func activeGoal(_ state: AppState, at now: Moment) throws -> ActiveGoalCard {
    guard case .active(let goal) = try goalCard(state, at: now) else {
        Issue.record("期望累计中目标，实际为空队列")
        throw PanelError.wrongBody
    }
    return goal
}

/// 在 `now` 时刻新建一个目标。
func creatingGoal(_ name: String, _ amount: Decimal, in state: AppState, at now: Moment) throws -> AppState {
    try apply(.createGoal(name: name, amount: amount), to: state, at: now).state
}

@Suite("目标：新建")
struct GoalCreationTests {
    @Test("AC-GOAL-01 本月累计 9000 时新建目标：累计额从 0 开始，之后只算新赚的钱")
    func firstGoalDoesNotBackdate() throws {
        // 2026-02-13 周五是 2 月第 10 个应出勤日，09:00 还没上班，本月累计 9000。
        let before = moment(2026, 2, 13, 9, 0)
        let state = try creatingGoal("Switch 2", 10000, in: try onboarded(at: before), at: before)
        #expect(snapshot(of: state, at: before).today?.monthToDate == 9000)

        let atCreation = try activeGoal(state, at: before)
        let at1100 = try activeGoal(state, at: moment(2026, 2, 13, 11, 0))

        #expect(atCreation.name == "Switch 2")
        #expect(atCreation.amountText == "¥0 / ¥10000")
        #expect(atCreation.progress == 0)
        #expect(at1100.amountText == "¥142.8571 / ¥10000")
    }

    @Test(
        "AC-GOAL-07 / PRD 4.3.5 #9 名称为空、只有空白、超过 20 字或金额不大于 0：提示【给目标起个名字，金额得大于 0】，不保存",
        arguments: [
            ("", Decimal(1000)),
            ("   ", Decimal(1000)),
            (String(repeating: "牛", count: 21), Decimal(1000)),
            ("Switch 2", Decimal(0)),
            ("Switch 2", Decimal(-1)),
        ]
    )
    func invalidGoalIsRejected(name: String, amount: Decimal) throws {
        let state = try onboarded()

        #expect(throws: CommandError.invalidGoal) { try creatingGoal(name, amount, in: state, at: standardDay(11, 0)) }
        #expect(CommandError.invalidGoal.message == "给目标起个名字，金额得大于 0")
        #expect(try goalCard(state, at: standardDay(11, 0)) == .empty("给自己定个目标吧"))
    }

    @Test("PRD 4.5.1 名称正好 20 字可以保存，首尾空白去掉")
    func twentyCharacterNameIsAccepted() throws {
        let name = String(repeating: "牛", count: 20)
        let state = try creatingGoal("  \(name) ", 1000, in: try onboarded(), at: standardDay(11, 0))

        #expect(try activeGoal(state, at: standardDay(11, 0)).name == name)
    }
}

@Suite("目标：面板目标区")
struct GoalCardTests {
    @Test("AC-GPRG-03 无任何目标：显示【给自己定个目标吧】")
    func emptyQueuePrompt() throws {
        #expect(try goalCard(try onboarded(), at: standardDay(11, 0)) == .empty("给自己定个目标吧"))
    }
}

@Suite("目标：预计完成")
struct GoalEstimateTests {
    @Test("AC-GPRG-01 4.5.3 算例：目标 10000，今天 15:00 累计额 3000：【还需搬砖 7 天】，日期为明天起第 7 个应出勤日")
    func standardEstimate() throws {
        // 2026-02-06 周五 15:00 新建：当天还剩 428.5714，加上 9、10 日各 1000，到 11 日 15:00 再赚 571.4286，累计额正好 3000。
        // 剩余 = 10000 - 3000 - 今日剩余可赚 428.5714 = 6571.4286，向上取整 7 天。
        // 明天 2 月 12 日 (周四) 起的应出勤日：12、13、16、17、18、19、20，第 7 个是 2 月 20 日。
        let created = moment(2026, 2, 6, 15, 0)
        let state = try creatingGoal("Switch 2", 10000, in: try onboarded(at: created), at: created)
        let card = try activeGoal(state, at: standardDay(15, 0))

        #expect(card.amountText == "¥3000 / ¥10000")
        #expect(card.estimate == "还需搬砖 7 天 · 2月20日")
    }

    @Test("AC-GPRG-02 剩余金额小于今日剩余可赚：【今天就能达成】")
    func reachableToday() throws {
        // 09:00 新建 500 元目标；11:00 已赚 142.8571，还差 357.1429，今日还能赚 857.1429。
        let state = try creatingGoal("键盘", 500, in: try onboarded(), at: standardDay(9, 0))

        #expect(try activeGoal(state, at: standardDay(11, 0)).estimate == "今天就能达成")
    }

    @Test("PRD 4.5.3 #2 扣除今日剩余可赚后正好为 0：也是【今天就能达成】")
    func reachableTodayExactly() throws {
        // 09:00 新建 1000 元目标；09:30 还没上班，剩余 1000，今日剩余可赚也是 1000。
        let state = try creatingGoal("键盘", 1000, in: try onboarded(), at: standardDay(9, 0))

        #expect(try activeGoal(state, at: standardDay(9, 30)).estimate == "今天就能达成")
    }

    @Test("PRD 4.5.3 #2 已下班不再扣除今日剩余可赚：还差 500 时明天就是第 1 个应出勤日")
    func offWorkCountsFromTomorrow() throws {
        let state = try creatingGoal("键盘", 1500, in: try onboarded(), at: standardDay(9, 0))

        #expect(try activeGoal(state, at: standardDay(18, 30)).estimate == "还需搬砖 1 天 · 2月12日")
    }

    @Test("PRD 4.5.3 #3 休息日从明天起数：周六还差 1500，第 2 个应出勤日是下周二")
    func restDaySkipsWeekend() throws {
        // 2026-02-14 周六 新建，15 日周日不上班，16 日周一、17 日周二。
        let saturday = moment(2026, 2, 14, 11, 0)
        let state = try creatingGoal("键盘", 1500, in: try onboarded(at: saturday), at: saturday)

        #expect(try activeGoal(state, at: saturday).estimate == "还需搬砖 2 天 · 2月17日")
    }

    @Test("PRD 4.5.3 #3 / D7 跨月仍按当月日薪估算：2 月 27 日下班后还差 3000，按 2 月日薪 1000 数 3 天到 3 月 4 日")
    func crossMonthUsesCurrentWage() throws {
        // 3 月只按双休有 22 个应出勤日，日薪 909.0909；若按 3 月日薪估算会是 4 天。
        let created = moment(2026, 2, 27, 18, 30)
        let state = try creatingGoal("键盘", 3000, in: try onboarded(at: created), at: created)

        #expect(try activeGoal(state, at: created).estimate == "还需搬砖 3 天 · 3月4日")
    }
}

@Suite("目标：累计与达成")
struct GoalProgressTests {
    /// 在 `now` 时刻推进到此刻。
    private func advanced(_ state: AppState, at now: Moment) throws -> AppState {
        try apply(.advance, to: state, at: now).state
    }

    @Test("PRD 4.5.2 上班中累计额达标后推进到此刻：目标变为已完成，记录完成时间，面板回到空队列")
    func completesWhileWorking() throws {
        // 09:00 新建 500 元目标；15:00 已赚 571.4286，超过 500。
        let state = try creatingGoal("键盘", 500, in: try onboarded(), at: standardDay(9, 0))
        let done = try advanced(state, at: standardDay(15, 0))

        #expect(done.goals.map(\.status) == [.completed(at: standardDay(15, 0).date)])
        #expect(try goalCard(done, at: standardDay(15, 0)) == .empty("给自己定个目标吧"))
    }

    @Test("PRD 4.5.2 累计额正好等于目标金额即完成：目标 1000，计划下班 18:00 今日已赚正好 1000")
    func completesExactlyAtAmount() throws {
        let state = try creatingGoal("键盘", 1000, in: try onboarded(), at: standardDay(9, 0))

        #expect(try advanced(state, at: standardDay(17, 59, 59)) == state)
        #expect(try advanced(state, at: standardDay(18, 0)).goals.map(\.status) == [.completed(at: standardDay(18, 0).date)])
    }

    @Test("PRD 4.5.2 未达标时推进到此刻不改变状态")
    func notYetReached() throws {
        let state = try creatingGoal("键盘", 500, in: try onboarded(), at: standardDay(9, 0))

        #expect(try advanced(state, at: standardDay(11, 0)) == state)
    }

    @Test("PRD 4.5.2 不变量 3 已完成目标冻结：之后再推进，完成时间不变")
    func completedGoalIsFrozen() throws {
        let state = try creatingGoal("键盘", 500, in: try onboarded(), at: standardDay(9, 0))
        let done = try advanced(state, at: standardDay(15, 0))

        #expect(try advanced(done, at: moment(2026, 3, 2, 15, 0)) == done)
    }

    @Test("PRD 4.5.1 累计收入跨月：2 月 26 日下班后新建，3 月 3 日 09:00 累计额 = 2 月 27 日 1000 + 3 月 2 日 20000/22")
    func accumulatesAcrossMonths() throws {
        let created = moment(2026, 2, 26, 18, 30)
        let state = try creatingGoal("键盘", 10000, in: try onboarded(at: created), at: created)

        #expect(try activeGoal(state, at: moment(2026, 3, 3, 9, 0)).amountText == "¥1909.0909 / ¥10000")
    }

    @Test("AC-GPRG 进度条：累计额 3000 / 10000 时为 0.3")
    func progressRatio() throws {
        let created = moment(2026, 2, 6, 15, 0)
        let state = try creatingGoal("Switch 2", 10000, in: try onboarded(at: created), at: created)

        #expect(try activeGoal(state, at: standardDay(15, 0)).progress == 0.3)
    }

    @Test("PRD 4.3.5 #17 累计额为负时进度显示 0：15:00 新建后系统时间拨回 11:00")
    func negativeAccumulationShowsZero() throws {
        let state = try creatingGoal("键盘", 1000, in: try onboarded(), at: standardDay(15, 0))
        let card = try activeGoal(state, at: standardDay(11, 0))

        #expect(card.progress == 0)
        #expect(card.amountText == "¥0 / ¥1000")
    }

    @Test("spec #1 推进到此刻：引导前什么也不做")
    func advanceBeforeOnboarding() throws {
        #expect(try advanced(AppState(), at: standardDay(11, 0)) == AppState())
    }
}

@Suite("目标：本期边界")
struct GoalScopeTests {
    @Test("PRD 4.5.2 不变量 1 已有累计中目标时暂不能再新建 (排队属于目标队列 #12)")
    func secondGoalIsRejected() throws {
        let state = try creatingGoal("键盘", 1000, in: try onboarded(), at: standardDay(9, 0))

        #expect(throws: CommandError.goalAlreadyAccumulating) {
            try creatingGoal("Switch 2", 3000, in: state, at: standardDay(11, 0))
        }
    }

    @Test("PRD 4.5.2 完成时队列为空：零头不保留，之后新建的目标从新建时刻起算")
    func newGoalAfterCompletion() throws {
        let state = try creatingGoal("键盘", 500, in: try onboarded(), at: standardDay(9, 0))
        let done = try apply(.advance, to: state, at: standardDay(15, 0)).state
        let again = try creatingGoal("Switch 2", 3000, in: done, at: standardDay(15, 0))

        #expect(try activeGoal(again, at: standardDay(15, 0)).amountText == "¥0 / ¥3000")
    }

    @Test("PRD 4.1.2 引导前不能新建目标")
    func requiresOnboarding() {
        #expect(throws: CommandError.notOnboarded) { try creatingGoal("键盘", 500, in: AppState(), at: standardDay(9, 0)) }
    }
}

@Suite("目标：目标管理列表")
struct GoalListTests {
    @Test("F8 列表：累计中在最前，已完成按完成时间倒序，带金额与完成日期")
    func rowsInOrder() throws {
        let first = try creatingGoal("键盘", 500, in: try onboarded(), at: standardDay(9, 0))
        let firstDone = try apply(.advance, to: first, at: standardDay(15, 0)).state
        let second = try creatingGoal("耳机", 300, in: firstDone, at: standardDay(15, 0))
        let secondDone = try apply(.advance, to: second, at: moment(2026, 2, 12, 15, 0)).state
        let third = try creatingGoal("Switch 2", 3000, in: secondDone, at: moment(2026, 2, 12, 15, 0))

        let rows = try #require(snapshot(of: third, at: moment(2026, 2, 13, 11, 0)).goals)
        // 2 月 12 日 15:00 新建，当天还剩 428.5714，加上 13 日 11:00 已赚 142.8571。
        #expect(rows.map { [$0.name, $0.statusLabel, $0.detail] } == [
            ["Switch 2", "累计中", "¥571.4286 / ¥3000"],
            ["耳机", "已完成", "¥300 · 2月12日达成"],
            ["键盘", "已完成", "¥500 · 2月11日达成"],
        ])
    }

    @Test("F8 列表：完成日期不在今年时带年份")
    func completedInEarlierYear() throws {
        let created = moment(2026, 12, 30, 9, 0)
        let state = try creatingGoal("键盘", 100, in: try onboarded(at: created), at: created)
        let done = try apply(.advance, to: state, at: moment(2026, 12, 30, 15, 0)).state

        #expect(try #require(snapshot(of: done, at: moment(2027, 1, 4, 9, 0)).goals).map(\.detail) == ["¥100 · 2026年12月30日达成"])
    }

    @Test("F8 没有目标时列表为空；引导前没有列表")
    func emptyList() throws {
        #expect(snapshot(of: try onboarded(), at: standardDay(11, 0)).goals == [])
        #expect(snapshot(of: AppState(), at: standardDay(11, 0)).goals == nil)
    }
}

@Suite("目标：重启")
struct GoalPersistenceTests {
    @Test("PRD 4.3.5 #14 目标重启后仍在：状态存成 JSON 再读回，累计额与完成记录不变")
    func goalsSurvivePersistence() throws {
        let first = try creatingGoal("键盘", 500, in: try onboarded(), at: standardDay(9, 0))
        let done = try apply(.advance, to: first, at: standardDay(15, 0)).state
        let state = try creatingGoal("Switch 2", 3000, in: done, at: standardDay(15, 0))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(snapshot(of: restored, at: standardDay(17, 0)) == snapshot(of: state, at: standardDay(17, 0)))
    }

    @Test("PRD 4.3.5 #14 #11 之前写出的状态文件没有目标，读入后队列为空")
    func oldFileWithoutGoals() throws {
        let state = try onboarded()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["goals"] = nil
        let restored = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(restored == state)
    }

    @Test(
        "PRD 4.3.5 #9 文件里的目标不合法时拒绝读入",
        arguments: [
            #"{"id":1,"name":"","amount":"500","status":"accumulating","baseline":"0"}"#,
            #"{"id":1,"name":"键盘","amount":"0","status":"accumulating","baseline":"0"}"#,
            #"{"id":1,"name":"键盘","amount":"500","status":"queued"}"#,
            #"{"id":1,"name":"键盘","amount":"500","status":"accumulating","baseline":"abc"}"#,
        ]
    )
    func invalidGoalIsRejected(goal: String) throws {
        let valid = #"{"id":1,"name":"键盘","amount":"500","status":"accumulating","baseline":"0"}"#
        #expect(throws: Never.self) { try JSONDecoder().decode(AppState.self, from: Data(#"{"goals":[\#(valid)]}"#.utf8)) }

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AppState.self, from: Data(#"{"goals":[\#(goal)]}"#.utf8)) }
    }
}
