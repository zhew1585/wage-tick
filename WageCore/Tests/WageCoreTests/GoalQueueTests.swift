import Foundation
import Testing
import WageCore

// 目标队列 (PRD 4.5.2、4.5.3 #5、F8、F9，issue #12)。
// 与 GoalTests 同一约定：除「接入节假日」外都用空节假日表，2026 年 2 月 20 个应出勤日，日薪 1000；
// 标准作息 10:00 至 18:00、午休 12:00 至 13:00，有效工时 7 小时。

/// 在 `now` 时刻执行一条命令，返回新状态。
private func sending(_ command: Command, to state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> AppState {
    try apply(command, to: state, at: now, holidays: holidays).state
}

/// 在 `now` 时刻依次新建若干目标 (名称、金额)。
private func creatingGoals(_ goals: [(String, Decimal)], in state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> AppState {
    try goals.reduce(state) { state, goal in
        try sending(.createGoal(name: goal.0, amount: goal.1), to: state, at: now, holidays: holidays)
    }
}

/// 目标管理列表；未完成引导时测试失败。
private func goalList(_ state: AppState, at now: Moment) throws -> GoalList {
    try #require(snapshot(of: state, at: now).goals)
}

/// 目标管理列表里攒钱队列的目标名称，按队列顺序，第一个是累计中。
private func queueNames(_ state: AppState, at now: Moment) throws -> [String] {
    try goalList(state, at: now).queue.map(\.name)
}

/// 面板目标区下方的队列部分；未完成引导时测试失败。
private func goalQueue(_ state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> GoalQueueSection? {
    try #require(snapshot(of: state, at: now, holidays: holidays).panel).goalQueue
}

/// 目标管理列表里某个名称的目标编号。
private func goalID(_ name: String, in state: AppState) throws -> Int {
    try #require(state.goals.first { $0.name == name }).id
}

/// 2026-02-11 09:00 引导后，依次新建 A 10000、B 3000、C 2500。
private func threeGoals() throws -> AppState {
    try creatingGoals([("A", 10000), ("B", 3000), ("C", 2500)], in: try onboarded(), at: standardDay(9, 0))
}

@Suite("目标队列：新建与达成")
struct GoalQueueCreationTests {
    @Test("AC-GOAL-02 已有累计中目标时新建：新目标排到队尾，状态为排队中")
    func secondGoalIsQueued() throws {
        let state = try creatingGoals([("键盘", 1000), ("Switch 2", 3000)], in: try onboarded(), at: standardDay(9, 0))

        #expect(state.goals.map(\.status.isQueued) == [false, true])
        #expect(try queueNames(state, at: standardDay(11, 0)) == ["键盘", "Switch 2"])
        #expect(try activeGoal(state, at: standardDay(11, 0)).name == "键盘")
    }

    @Test("AC-GOAL-03 A 1000 元完成时累计额 1000.0397：B 从 0.0397 开始")
    func carryOverToNextGoal() throws {
        // 2 月 10 日 17:59:59 新建，当天还剩 1 秒可赚 0.0397；11 日 18:00 累计额 1000.0397。
        let created = moment(2026, 2, 10, 17, 59, 59)
        let state = try creatingGoals([("A", 1000), ("B", 3000)], in: try onboarded(at: created), at: created)
        let done = try sending(.advance, to: state, at: standardDay(18, 0))

        #expect(done.goals.map(\.status.isQueued) == [false, false])
        #expect(done.goals[0].status == .completed(at: standardDay(18, 0).date))
        let next = try activeGoal(done, at: standardDay(18, 0))
        #expect(next.name == "B")
        #expect(next.amountText == "¥0.0397 / ¥3000")
    }

    @Test("PRD 4.5.2 结转后仍达标继续完成：A 500、B 300 同一次推进里都完成，C 带着 200 开始")
    func chainedCompletion() throws {
        let state = try creatingGoals([("A", 500), ("B", 300), ("C", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let done = try sending(.advance, to: state, at: standardDay(18, 0))

        let at = standardDay(18, 0).date
        #expect(Array(done.goals.map(\.status).prefix(2)) == [.completed(at: at), .completed(at: at)])
        #expect(try activeGoal(done, at: standardDay(18, 0)).amountText == "¥200 / ¥3000")
    }

    @Test("spec #1 推进到此刻依次处理：跨过 18:00 的一次推进里 A、B 连续完成、C 激活，先各发一条达成事件 (#13)，下班事件照常产生")
    func advanceCompletesQueueAndNotifiesOffWork() throws {
        let state = try creatingGoals([("A", 500), ("B", 300), ("C", 3000)], in: try onboarded(), at: standardDay(9, 0))
        // 10:00 还没赚钱，什么都不发生；下一次刷新直接到 18:00 (如睡眠恢复)，累计额 1000。
        let before = try apply(.advance, to: state, at: standardDay(10, 0))
        #expect(before.state.goals == state.goals)
        #expect(before.events.isEmpty)
        let atEnd = try apply(.advance, to: before.state, at: standardDay(18, 0))

        #expect(atEnd.events == [
            .goalReached(message: "🎉 目标「A」达成"),
            .goalReached(message: "🎉 目标「B」达成"),
            .offWork(message: "今日 1000 元已到账，可以走了"),
        ])
        #expect(atEnd.state.goals.map(\.status).filter(\.isQueued).isEmpty)
        #expect(try activeGoal(atEnd.state, at: standardDay(18, 0)).amountText == "¥200 / ¥3000")
    }

    @Test("PRD 4.5.2 不变量 3 / AC-GOAL-08 完成后当天再扣钱：已完成目标不变，只有当前目标累计额减少")
    func completedGoalFrozenAfterDeduction() throws {
        // A 500 在 15:00 完成 (今日已赚 571.4286)，B 带着 71.4286 开始。
        let state = try creatingGoals([("A", 500), ("B", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let done = try sending(.advance, to: state, at: standardDay(15, 0))
        let fined = try sending(
            .addDeduction(DeductionInput(amount: .fixed(50), reason: .late, note: "")),
            to: done, at: standardDay(16, 0)
        )

        #expect(fined.goals[0] == done.goals[0])
        // 16:00 已工作 5 小时，今日已赚 = 950 × 5/7 = 678.5714，B 累计额 = 678.5714 - 500；不扣钱时是 214.2857。
        #expect(try activeGoal(done, at: standardDay(16, 0)).amountText == "¥214.2857 / ¥3000")
        #expect(try activeGoal(fined, at: standardDay(16, 0)).amountText == "¥178.5714 / ¥3000")
    }
}

@Suite("目标队列：删除")
struct GoalQueueDeletionTests {
    @Test("AC-GOAL-04 / D5 累计中 A 已累计 300，删除 A：B 成为累计中，累计额 300")
    func deletingActiveGoalPassesBaseline() throws {
        // 13:06 已工作 2.1 小时，今日已赚 300。
        let state = try creatingGoals([("A", 1000), ("B", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let deleted = try sending(.deleteGoal(id: try goalID("A", in: state)), to: state, at: standardDay(13, 6))

        #expect(deleted.goals.map(\.name) == ["B"])
        let next = try activeGoal(deleted, at: standardDay(13, 6))
        #expect(next.name == "B")
        #expect(next.amountText == "¥300 / ¥3000")
        #expect(try activeGoal(deleted, at: standardDay(14, 6)).amountText == "¥442.8571 / ¥3000")
    }

    @Test("PRD 4.5.2 删除累计中 A 后 B 继承的累计额已达标：B 立即完成")
    func inheritedBaselineCompletesNext() throws {
        let state = try creatingGoals([("A", 1000), ("B", 200), ("C", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let deleted = try sending(.deleteGoal(id: try goalID("A", in: state)), to: state, at: standardDay(13, 6))

        #expect(deleted.goals.map(\.status).first == .completed(at: standardDay(13, 6).date))
        #expect(try activeGoal(deleted, at: standardDay(13, 6)).amountText == "¥100 / ¥3000")
    }

    @Test("PRD 4.5.2 删除排队中目标：只从队列移除，累计中目标不受影响")
    func deletingQueuedGoal() throws {
        let state = try threeGoals()
        let deleted = try sending(.deleteGoal(id: try goalID("B", in: state)), to: state, at: standardDay(13, 6))

        #expect(try queueNames(deleted, at: standardDay(13, 6)) == ["A", "C"])
        #expect(try activeGoal(deleted, at: standardDay(13, 6)).amountText == "¥300 / ¥10000")
    }

    @Test("PRD 4.5.2 删除唯一的累计中目标：面板回到【给自己定个目标吧】")
    func deletingOnlyGoal() throws {
        let state = try creatingGoal("A", 1000, in: try onboarded(), at: standardDay(9, 0))
        let deleted = try sending(.deleteGoal(id: try goalID("A", in: state)), to: state, at: standardDay(11, 0))

        #expect(try goalCard(deleted, at: standardDay(11, 0)) == .empty("给自己定个目标吧"))
        #expect(try goalList(deleted, at: standardDay(11, 0)) == GoalList.empty)
    }

    @Test("F8 删除已完成目标：从列表移除，当前目标不受影响")
    func deletingCompletedGoal() throws {
        let state = try creatingGoals([("A", 500), ("B", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let done = try sending(.advance, to: state, at: standardDay(15, 0))
        let deleted = try sending(.deleteGoal(id: try goalID("A", in: done)), to: done, at: standardDay(16, 0))

        #expect(try goalList(deleted, at: standardDay(16, 0)) == GoalList(queue: goalList(done, at: standardDay(16, 0)).queue, completed: []))
        #expect(try activeGoal(deleted, at: standardDay(16, 0)) == activeGoal(done, at: standardDay(16, 0)))
    }

    @Test("删除不存在的目标：提示【这个目标已经不在了】")
    func deletingMissingGoal() throws {
        let state = try threeGoals()

        #expect(throws: CommandError.goalNotFound) { try sending(.deleteGoal(id: 99), to: state, at: standardDay(11, 0)) }
        #expect(CommandError.goalNotFound.message == "这个目标已经不在了")
    }
}

@Suite("目标队列：排序")
struct GoalQueueOrderTests {
    @Test("AC-GOAL-05 / D6 累计中 A (1000) 已累计 300，把排队中 C (2000) 拖到 A 之前：C 成为累计中，累计额 300；A 退回排队中")
    func movingQueuedGoalFirstTakesOverAccumulated() throws {
        // 13:06 已工作 2.1 小时，今日已赚 300。
        let state = try creatingGoals([("A", 1000), ("B", 3000), ("C", 2000)], in: try onboarded(), at: standardDay(9, 0))
        let ids = try ["C", "A", "B"].map { try goalID($0, in: state) }
        let result = try apply(.reorderGoals(ids: ids), to: state, at: standardDay(13, 6))

        #expect(result.events.isEmpty)
        #expect(try queueNames(result.state, at: standardDay(13, 6)) == ["C", "A", "B"])
        let active = try activeGoal(result.state, at: standardDay(13, 6))
        #expect(active.name == "C")
        #expect(active.amountText == "¥300 / ¥2000")
        #expect(result.state.goals.first { $0.name == "A" }?.status == .queued)
        // C 接着从 A 的起算基准往上累计。
        #expect(try activeGoal(result.state, at: standardDay(14, 6)).amountText == "¥442.8571 / ¥2000")
    }

    @Test("AC-GOAL-09 / D6 累计中 A 已累计 300，把排队中 B (200) 拖到最前：B 立即完成，零头 100 结转给新的第一个")
    func movingReachedGoalFirstCompletesIt() throws {
        let state = try creatingGoals([("A", 1000), ("B", 200), ("C", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let ids = try ["B", "A", "C"].map { try goalID($0, in: state) }
        let result = try apply(.reorderGoals(ids: ids), to: state, at: standardDay(13, 6))

        #expect(result.state.goals.first { $0.name == "B" }?.status == .completed(at: standardDay(13, 6).date))
        #expect(result.events == [.goalReached(message: "🎉 目标「B」达成")])
        #expect(snapshot(of: result.state, at: standardDay(13, 6)).celebration?.goalID == (try goalID("B", in: state)))
        #expect(try queueNames(result.state, at: standardDay(13, 6)) == ["A", "C"])
        #expect(try activeGoal(result.state, at: standardDay(13, 6)).amountText == "¥100 / ¥1000")
    }

    @Test("D6 换下来的 A 退回排队中，之后再被激活时按激活时刻重新起算，不带回原来累计的钱")
    func swappedOutGoalRestartsWhenActivatedAgain() throws {
        // 13:06 A 已累计 300 时换成 B (500)；15:00 累计 571.4286，B 完成，A 只带着零头 71.4286 开始。
        let state = try creatingGoals([("A", 10000), ("B", 500)], in: try onboarded(), at: standardDay(9, 0))
        let ids = try ["B", "A"].map { try goalID($0, in: state) }
        let swapped = try sending(.reorderGoals(ids: ids), to: state, at: standardDay(13, 6))
        let done = try sending(.advance, to: swapped, at: standardDay(15, 0))

        let active = try activeGoal(done, at: standardDay(15, 0))
        #expect(active.name == "A")
        #expect(active.amountText == "¥71.4286 / ¥10000")
    }

    @Test("D6 换下来再换回去：A 从此刻继承当前第一个的累计额，不是自己原来的起算基准")
    func swappingBackInheritsCurrentAccumulated() throws {
        // 13:06 把 B 换上 (300)，15:00 再把 A 换回来：A 继承 B 的起算基准，累计额 571.4286。
        let state = try creatingGoals([("A", 10000), ("B", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let a = try goalID("A", in: state), b = try goalID("B", in: state)
        let swapped = try sending(.reorderGoals(ids: [b, a]), to: state, at: standardDay(13, 6))
        let back = try sending(.reorderGoals(ids: [a, b]), to: swapped, at: standardDay(15, 0))

        #expect(try activeGoal(back, at: standardDay(15, 0)).amountText == "¥571.4286 / ¥10000")
        #expect(back.goals.first { $0.id == b }?.status == .queued)
    }

    @Test("PRD 4.5.2 只调排队中目标之间的顺序：累计中目标和它的累计额不变，下一个激活的是 C")
    func reorderQueuedGoals() throws {
        let state = try creatingGoals([("A", 500), ("B", 3000), ("C", 2500)], in: try onboarded(), at: standardDay(9, 0))
        let ids = try ["A", "C", "B"].map { try goalID($0, in: state) }
        let result = try apply(.reorderGoals(ids: ids), to: state, at: standardDay(11, 0))

        #expect(result.events.isEmpty)
        #expect(try queueNames(result.state, at: standardDay(11, 0)) == ["A", "C", "B"])
        #expect(result.state.goals.first { $0.name == "A" }?.status == state.goals.first { $0.name == "A" }?.status)
        #expect(try activeGoal(result.state, at: standardDay(11, 0)) == activeGoal(state, at: standardDay(11, 0)))
        let done = try sending(.advance, to: result.state, at: standardDay(15, 0))
        #expect(try activeGoal(done, at: standardDay(15, 0)).name == "C")
    }

    @Test("顺序不变时什么都不变")
    func unchangedOrder() throws {
        let state = try threeGoals()
        let ids = try ["A", "B", "C"].map { try goalID($0, in: state) }
        let result = try apply(.reorderGoals(ids: ids), to: state, at: standardDay(13, 6))

        #expect(result.state == state)
        #expect(result.events.isEmpty)
    }

    @Test(
        "PRD 4.5.2 / AC-GOAL-10 排序列表必须正好是攒钱队列：少一个、多一个、重复或混入已完成都提示【这个目标已经不在了】",
        arguments: [["A", "B"], ["A", "B", "C", "C"], ["A", "B", "C", "D"], ["D", "A", "B", "C"]]
    )
    func reorderWithStaleList(names: [String]) throws {
        let finished = try creatingGoal("D", 100, in: try onboarded(), at: standardDay(9, 0))
        let done = try sending(.advance, to: finished, at: standardDay(11, 0))
        let state = try creatingGoals([("A", 10000), ("B", 3000), ("C", 2500)], in: done, at: standardDay(11, 0))
        let ids = try names.map { try goalID($0, in: state) }

        #expect(throws: CommandError.goalNotFound) { try sending(.reorderGoals(ids: ids), to: state, at: standardDay(11, 0)) }
    }
}

@Suite("目标队列：编辑")
struct GoalQueueEditTests {
    @Test("AC-GOAL-06 累计额 800 时把金额从 1000 改为 500：立即完成并激活下一个，零头 300 结转")
    func loweringAmountCompletesImmediately() throws {
        // 16:36 已工作 5.6 小时，今日已赚 800。
        let state = try creatingGoals([("A", 1000), ("B", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let edited = try sending(.editGoal(id: try goalID("A", in: state), name: "A", amount: 500), to: state, at: standardDay(16, 36))

        #expect(edited.goals.map(\.status).first == .completed(at: standardDay(16, 36).date))
        #expect(edited.goals.first?.amount == 500)
        let next = try activeGoal(edited, at: standardDay(16, 36))
        #expect(next.name == "B")
        #expect(next.amountText == "¥300 / ¥3000")
    }

    @Test("PRD 4.5.2 累计中目标改名、改大金额：仍在累计中，累计额不变")
    func editingActiveGoal() throws {
        let state = try creatingGoals([("A", 1000), ("B", 3000)], in: try onboarded(), at: standardDay(9, 0))
        let edited = try sending(.editGoal(id: try goalID("A", in: state), name: " 新键盘 ", amount: 2000), to: state, at: standardDay(16, 36))

        let card = try activeGoal(edited, at: standardDay(16, 36))
        #expect(card.name == "新键盘")
        #expect(card.amountText == "¥800 / ¥2000")
    }

    @Test("PRD 4.5.2 排队中目标可改名称和金额，仍排在原位")
    func editingQueuedGoal() throws {
        let state = try threeGoals()
        let edited = try sending(.editGoal(id: try goalID("B", in: state), name: "耳机", amount: 1200), to: state, at: standardDay(11, 0))

        let queue = try goalList(edited, at: standardDay(11, 0)).queue
        #expect(queue.map { [$0.name, $0.amountText] } == [["A", "¥10000"], ["耳机", "¥1200"], ["C", "¥2500"]])
        #expect(queue.first?.asFirst.amountText == "¥142.8571 / ¥10000")
    }

    @Test("PRD 4.5.2 不变量 3 已完成目标不能编辑：提示【已完成的目标不能再改】")
    func completedGoalIsNotEditable() throws {
        let state = try creatingGoal("A", 500, in: try onboarded(), at: standardDay(9, 0))
        let done = try sending(.advance, to: state, at: standardDay(15, 0))

        #expect(throws: CommandError.goalCompleted) {
            try sending(.editGoal(id: try goalID("A", in: done), name: "A", amount: 5000), to: done, at: standardDay(16, 0))
        }
        #expect(CommandError.goalCompleted.message == "已完成的目标不能再改")
    }

    @Test("AC-GOAL-07 编辑时名称留空或金额不大于 0：提示【给目标起个名字，金额得大于 0】", arguments: [("", Decimal(1000)), ("A", Decimal(0))])
    func invalidEditIsRejected(name: String, amount: Decimal) throws {
        let state = try threeGoals()

        #expect(throws: CommandError.invalidGoal) {
            try sending(.editGoal(id: try goalID("B", in: state), name: name, amount: amount), to: state, at: standardDay(11, 0))
        }
    }

    @Test("编辑不存在的目标：提示【这个目标已经不在了】")
    func editingMissingGoal() throws {
        #expect(throws: CommandError.goalNotFound) {
            try sending(.editGoal(id: 99, name: "A", amount: 100), to: try threeGoals(), at: standardDay(11, 0))
        }
    }
}

@Suite("目标队列：面板目标区")
struct GoalQueuePanelTests {
    @Test("AC-GPRG-05 1 个累计中、2 个排队中：默认只显示累计中目标和【显示更多 (2)】")
    func collapsedByDefault() throws {
        let queue = try #require(try goalQueue(try threeGoals(), at: standardDay(11, 0)))

        #expect(try activeGoal(try threeGoals(), at: standardDay(11, 0)).name == "A")
        #expect(queue.queued == [])
        #expect(queue.toggleTitle == "显示更多 (2)")
    }

    @Test("AC-GPRG-06 展开：按队列顺序显示 3 个，排队中显示【排队中 · 预计 M月D日】，底部【收起】")
    func expandedShowsQueue() throws {
        // A 10000：11:00 累计额 142.8571，扣除今日剩余可赚 857.1429 后还差 9000，9 天到 2 月 24 日。
        // B 3000：2 月 24 日之后数 3 个应出勤日到 2 月 27 日；C 2500：再数 3 个到 3 月 4 日。
        let state = try sending(.toggleGoalQueueExpanded, to: try threeGoals(), at: standardDay(11, 0))
        let queue = try #require(try goalQueue(state, at: standardDay(11, 0)))

        #expect(try activeGoal(state, at: standardDay(11, 0)).estimate == "还需搬砖 9 天 · 2月24日")
        #expect(queue.queued.map { [$0.name, $0.amountText, $0.estimate] } == [
            ["B", "¥3000", "排队中 · 预计 2月27日"],
            ["C", "¥2500", "排队中 · 预计 3月4日"],
        ])
        #expect(queue.toggleTitle == "收起")
    }

    @Test("F9 收起：再切换一次回到【显示更多 (2)】")
    func collapseAgain() throws {
        let expanded = try sending(.toggleGoalQueueExpanded, to: try threeGoals(), at: standardDay(11, 0))
        let collapsed = try sending(.toggleGoalQueueExpanded, to: expanded, at: standardDay(11, 0))

        #expect(try goalQueue(collapsed, at: standardDay(11, 0))?.toggleTitle == "显示更多 (2)")
    }

    @Test("AC-GPRG-07 1 个累计中、4 个排队中：收起时【显示更多 (4)】，展开只显示前 3 个")
    func expandedShowsAtMostThree() throws {
        let goals: [(String, Decimal)] = [("A", 10000), ("B", 3000), ("C", 2500), ("D", 100), ("E", 100)]
        let state = try creatingGoals(goals, in: try onboarded(), at: standardDay(9, 0))
        let expanded = try sending(.toggleGoalQueueExpanded, to: state, at: standardDay(11, 0))

        #expect(try goalQueue(state, at: standardDay(11, 0))?.toggleTitle == "显示更多 (4)")
        #expect(try goalQueue(expanded, at: standardDay(11, 0))?.queued.map(\.name) == ["B", "C"])
    }

    @Test("AC-GPRG-08 只有 1 个累计中目标：不显示【显示更多】；没有目标时也不显示")
    func singleGoalHasNoQueue() throws {
        let single = try creatingGoal("A", 1000, in: try onboarded(), at: standardDay(9, 0))

        #expect(try goalQueue(single, at: standardDay(11, 0)) == nil)
        #expect(try goalQueue(try onboarded(), at: standardDay(11, 0)) == nil)
    }

    @Test("PRD 4.5.3 #5 累计中目标今天就能达成：第一个排队目标从明天起数")
    func queuedAfterReachableToday() throws {
        // A 500 今天就能达成；B 2000 从 2 月 12 日起数 2 个应出勤日到 13 日。
        let state = try creatingGoals([("A", 500), ("B", 2000)], in: try onboarded(), at: standardDay(9, 0))
        let expanded = try sending(.toggleGoalQueueExpanded, to: state, at: standardDay(11, 0))

        #expect(try activeGoal(expanded, at: standardDay(11, 0)).estimate == "今天就能达成")
        #expect(try goalQueue(expanded, at: standardDay(11, 0))?.queued.map(\.estimate) == ["排队中 · 预计 2月13日"])
    }

    @Test("PRD 4.5.3 #5 / D7 预计完成日不在今年：【排队中 · 预计 YYYY年M月】，仍按当月日薪数")
    func queuedInNextYear() throws {
        // 2026 年 12 月按双休 23 个应出勤日，日薪 869.5652。
        // 12 月 28 日周一下班后：A 1000 数 2 天到 30 日；B 2000 数 3 天：31 日、2027 年 1 月 1 日、4 日。
        let created = moment(2026, 12, 28, 18, 30)
        let state = try creatingGoals([("A", 1000), ("B", 2000)], in: try onboarded(at: created), at: created)
        let expanded = try sending(.toggleGoalQueueExpanded, to: state, at: created)

        #expect(try activeGoal(expanded, at: created).estimate == "还需搬砖 2 天 · 12月30日")
        #expect(try goalQueue(expanded, at: created)?.queued.map(\.estimate) == ["排队中 · 预计 2027年1月"])
    }

    @Test("PRD 4.5.3 #5 排队中目标按节假日数：A 在调休的 2 月 14 日完成，B 跳过春节放假到 2 月 25 日")
    func queuedSkipsSpringFestival() throws {
        // 2 月 13 日周五下班后，日薪 1250：A 1250 数 1 天到 14 日 (调休上班)；B 2500 数 2 天，跳过 15 日至 23 日到 25 日。
        let created = moment(2026, 2, 13, 18, 30)
        let state = try creatingGoals([("A", 1250), ("B", 2500)], in: try onboarded(at: created), at: created, holidays: springFestival)
        let expanded = try sending(.toggleGoalQueueExpanded, to: state, at: created, holidays: springFestival)

        #expect(try goalQueue(expanded, at: created, holidays: springFestival)?.queued.map(\.estimate) == ["排队中 · 预计 2月25日"])
    }
}

/// 2026 年春节放假安排：2 月 15 日至 23 日放假，2 月 14 日、28 日周六调休上班，2 月应出勤 16 天。
private let springFestival = HolidayTable(days: Dictionary(uniqueKeysWithValues:
    (15...23).map { (LocalDate(year: 2026, month: 2, day: $0), HolidayKind.holiday) }
        + [14, 28].map { (LocalDate(year: 2026, month: 2, day: $0), HolidayKind.makeupDay) }
))

@Suite("目标队列：展开状态与重启")
struct GoalQueuePersistenceTests {
    @Test("O3 首次默认收起")
    func collapsedOnFirstUse() throws {
        #expect(snapshot(of: try onboarded(), at: standardDay(11, 0)).settings.goalQueueExpanded == false)
    }

    @Test("AC-GPRG-09 / O3 展开后关闭面板再打开 (状态存成 JSON 再读回)：仍为展开")
    func expandedSurvivesRestart() throws {
        let expanded = try sending(.toggleGoalQueueExpanded, to: try threeGoals(), at: standardDay(11, 0))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(expanded))

        #expect(restored == expanded)
        #expect(try goalQueue(restored, at: standardDay(11, 0))?.toggleTitle == "收起")
    }

    @Test("PRD 4.3.5 #14 #12 之前写出的界面设置没有展开状态：读入后为收起")
    func oldSettingsWithoutExpandedState() throws {
        let settings = try JSONDecoder().decode(InterfaceSettings.self, from: Data(#"{"bossMode":true}"#.utf8))

        #expect(settings.goalQueueExpanded == false)
        #expect(settings.bossMode == true)
    }

    @Test("PRD 4.3.5 #14 排队中目标重启后仍在，顺序不变")
    func queueSurvivesRestart() throws {
        let state = try threeGoals()
        let ids = try ["A", "C", "B"].map { try goalID($0, in: state) }
        let reordered = try sending(.reorderGoals(ids: ids), to: state, at: standardDay(11, 0))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(reordered))

        #expect(restored == reordered)
        #expect(try queueNames(restored, at: standardDay(11, 0)) == ["A", "C", "B"])
    }
}

@Suite("目标队列：目标管理列表")
struct GoalQueueListTests {
    @Test("F8 / AC-GOAL-10 列表分两组：攒钱队列 (按队列顺序，第一个是累计中) 与已完成 (沉底)")
    func rowsGrouped() throws {
        let first = try creatingGoal("D", 100, in: try onboarded(), at: standardDay(9, 0))
        let done = try sending(.advance, to: first, at: standardDay(11, 0))
        let state = try creatingGoals([("A", 10000), ("B", 3000.5), ("C", 2500)], in: done, at: standardDay(11, 0))

        let list = try goalList(state, at: standardDay(11, 0))
        #expect(list.queue.map { [$0.name, $0.amountText, $0.amountInput] } == [
            ["A", "¥10000", "10000"],
            ["B", "¥3000.5", "3000.5"],
            ["C", "¥2500", "2500"],
        ])
        #expect(list.completed.map { [$0.name, $0.amountText, $0.completedText] } == [["D", "¥100", "2月11日达成"]])
    }

    @Test("F8 攒钱队列第一个带累计中的进度、累计额、预计完成，与面板目标区同一份")
    func firstRowIsAccumulating() throws {
        let state = try threeGoals()
        let list = try goalList(state, at: standardDay(11, 0))

        #expect(list.queue.first?.asFirst == (try activeGoal(state, at: standardDay(11, 0))))
    }

    @Test("D6 排队中目标也带排到第一个时的样子：继承当前已累计的钱，供拖到最前时即时预览")
    func queuedRowsPreviewAsFirst() throws {
        // 13:06 已累计 300：B 3000 排到最前时还差 2700，扣除今日剩余 700 后 2 天到 2 月 13 日；C 200 换上即达标。
        let state = try creatingGoals([("A", 10000), ("B", 3000), ("C", 200)], in: try onboarded(), at: standardDay(9, 0))
        let previews = try goalList(state, at: standardDay(13, 6)).queue.dropFirst().map(\.asFirst)

        #expect(previews.map { [$0.name, $0.amountText, $0.estimate] } == [
            ["B", "¥300 / ¥3000", "还需搬砖 2 天 · 2月13日"],
            ["C", "¥300 / ¥200", "已经攒够，排到第一个就达成"],
        ])
        #expect(abs(previews[0].progress - 0.1) < 1e-9)
        #expect(previews[1].progress == 1)
    }
}
