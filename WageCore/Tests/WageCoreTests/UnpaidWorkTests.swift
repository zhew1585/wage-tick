import Foundation
import Testing
import WageCore

// 白干计时 (PRD 4.4.3、F7)。标准算例：日薪 1000，标准工时 7 小时，时薪 142.8571。

/// 在 `now` 时刻执行一条命令，返回新状态。
private func applied(_ command: Command, to state: AppState, at now: Moment) throws -> AppState {
    try apply(command, to: state, at: now).state
}

/// 在 `from` 开始、`to` 停止一段白干。
private func unpaidWork(_ state: AppState, from: Moment, to: Moment) throws -> AppState {
    try applied(.stopUnpaidWork, to: applied(.startUnpaidWork, to: state, at: from), at: to)
}

@Suite("白干计时：时长与倒贴")
struct UnpaidWorkAmountTests {
    @Test("AC-OT-02 18:00 开始 19:30 停止：白干 1 小时 30 分，相当于倒贴 ¥214.2857")
    func standardExample() throws {
        let state = try unpaidWork(try onboarded(), from: standardDay(18, 0), to: standardDay(19, 30))
        let today = try #require(snapshot(of: state, at: standardDay(19, 30)).today)

        #expect(today.unpaidWork.milliseconds == 90 * 60 * 1000)
        #expect(rounded4(today.unpaidWork.owed) == Decimal(string: "214.2857")!)
        #expect(try attendancePanel(state, at: standardDay(19, 30)).caption == "今日白干 1:30 · 倒贴 ¥214.29")
    }

    @Test("AC-OT-07 同一天两段各 30 分钟：白干时长 1 小时")
    func segmentsAddUp() throws {
        let first = try unpaidWork(try onboarded(), from: standardDay(18, 0), to: standardDay(18, 30))
        let both = try unpaidWork(first, from: standardDay(19, 0), to: standardDay(19, 30))
        let today = try #require(snapshot(of: both, at: standardDay(20, 0)).today)

        #expect(today.unpaidWork.milliseconds == 60 * 60 * 1000)
        #expect(try attendancePanel(both, at: standardDay(20, 0)).caption == "今日白干 1:00 · 倒贴 ¥142.86")
    }

    @Test("AC-OT-06 计时中退出，10 分钟后打开：期间没有任何命令，白干时长包含这 10 分钟")
    func keepsCountingWhileQuit() throws {
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(running))
        let reopened = try applied(.advance, to: restored, at: standardDay(18, 10))
        let unpaid = try #require(snapshot(of: reopened, at: standardDay(18, 10)).today).unpaidWork

        #expect(unpaid.isRunning)
        #expect(unpaid.milliseconds == 10 * 60 * 1000)
    }

    @Test("PRD 4.4.3 #4 时薪按作息的标准工时计算：默认作息 8 小时，白干 1 小时倒贴 1000 ÷ 8 = ¥125")
    func hourlyWageFollowsStandardHours() throws {
        let state = try unpaidWork(try onboarded(schedule: .default), from: standardDay(18, 0), to: standardDay(19, 0))

        #expect(try attendancePanel(state, at: standardDay(19, 0)).caption == "今日白干 1:00 · 倒贴 ¥125")
    }
}

@Suite("白干计时：不影响收入")
struct UnpaidWorkIncomeTests {
    @Test("AC-OT-03 白干计时前后：今日结算、本月累计、菜单栏数字不变")
    func incomeUnchanged() throws {
        let plain = try onboarded()
        let worked = try unpaidWork(plain, from: standardDay(18, 0), to: standardDay(19, 30))
        let running = try applied(.startUnpaidWork, to: plain, at: standardDay(18, 0))

        for state in [worked, running] {
            let before = try #require(snapshot(of: plain, at: standardDay(19, 30)).today)
            let after = try #require(snapshot(of: state, at: standardDay(19, 30)).today)
            #expect(after.status == .offWork)
            #expect(after.earnings == before.earnings)
            #expect(after.monthToDate == before.monthToDate)
            #expect(snapshot(of: state, at: standardDay(19, 30)).menuBar.text == "1000.0000")
        }
    }

    @Test("AC-OT-04 周六被迫营业 1 小时：白干时长 1 小时，结算仍为 0，本月累计不变")
    func forcedOnRestDay() throws {
        // 2026-02-14 周六；2 月 2 日至 13 日共 10 个应出勤日。
        let saturday = { (hour: Int) in moment(2026, 2, 14, hour, 0) }
        let state = try unpaidWork(try onboarded(), from: saturday(10), to: saturday(11))
        let today = try #require(snapshot(of: state, at: saturday(12)).today)

        #expect(today.status == .restDay)
        #expect(today.unpaidWork.milliseconds == 60 * 60 * 1000)
        #expect(today.earnings == nil)
        #expect(today.monthToDate == 10000)
        #expect(snapshot(of: state, at: saturday(12)).menuBar.text == nil)
    }
}

@Suite("白干计时：可用条件")
struct UnpaidWorkAvailabilityTests {
    @Test("AC-OT-01 15:00 上班中：没有「我还没走」按钮，也不能开始计时")
    func notWhileWorking() throws {
        let state = try onboarded()

        #expect(snapshot(of: state, at: standardDay(15, 0)).panel?.unpaidWorkButton == nil)
        #expect(throws: CommandError.unpaidWorkUnavailable) {
            try apply(.startUnpaidWork, to: state, at: standardDay(15, 0))
        }
    }

    @Test("PRD 4.4.3 #1 未上班、干饭中也不能开始", arguments: [(9, 0), (12, 30)])
    func notBeforeWorkOrDuringLunch(time: (Int, Int)) throws {
        let now = standardDay(time.0, time.1)

        #expect(snapshot(of: try onboarded(), at: now).panel?.unpaidWorkButton == nil)
        #expect(throws: CommandError.unpaidWorkUnavailable) {
            try apply(.startUnpaidWork, to: try onboarded(), at: now)
        }
    }

    @Test("PRD 4.4.3 #1 已下班为「我还没走」，休息日为「被迫营业」")
    func buttonTitles() throws {
        let state = try onboarded()

        #expect(snapshot(of: state, at: standardDay(18, 30)).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "我还没走", command: .startUnpaidWork))
        #expect(snapshot(of: state, at: moment(2026, 2, 14, 10, 0)).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "被迫营业", command: .startUnpaidWork))
    }

    @Test("PRD 4.4.3 #2 同一时间只能有一段：计时中再开始被拒；没在计时不能停止")
    func oneAtATime() throws {
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))

        #expect(throws: CommandError.unpaidWorkAlreadyRunning) {
            try apply(.startUnpaidWork, to: running, at: standardDay(18, 5))
        }
        #expect(throws: CommandError.unpaidWorkNotRunning) {
            try apply(.stopUnpaidWork, to: try onboarded(), at: standardDay(18, 5))
        }
    }

    @Test("计时中按钮为「终于下班了」，停止后变回「我还没走」，可以再开一段")
    func stopButtonThenStartAgain() throws {
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let stopped = try applied(.stopUnpaidWork, to: running, at: standardDay(18, 30))

        #expect(snapshot(of: running, at: standardDay(18, 10)).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "终于下班了", command: .stopUnpaidWork))
        #expect(snapshot(of: stopped, at: standardDay(18, 40)).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "我还没走", command: .startUnpaidWork))
    }
}

@Suite("白干计时：面板与菜单栏")
struct UnpaidWorkPanelTests {
    @Test("AC-HOME-10 18:00 点「我还没走」，19:05:12 打开：标签【白干中】、主数字 ¥155.2381、小字含【18:00 起 · 已白干 1:05:12】，统计行为今日结算、距离周末、本月累计")
    func runningPanel() throws {
        let state = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let panel = try #require(snapshot(of: state, at: standardDay(19, 5, 12)).panel)

        #expect(panel.statusLabel == "白干中")
        // 扣款一项随扣钱 (#7) 加入，与已下班的统计行共用同一份。
        #expect(panel.body == .unpaidWork(UnpaidWorkPanel(
            label: "今日已倒贴",
            headline: "¥155.2381",
            caption: "18:00 起 · 已白干 1:05:12",
            stats: [
                StatItem(title: "今日结算", value: "¥1000"),
                StatItem(title: "距离周末", value: "3 天", isHighlighted: true),
                StatItem(title: "本月累计", value: "¥8000"),
            ],
            isRestDay: false
        )))
        #expect(snapshot(of: state, at: standardDay(19, 5, 12)).today?.isRolling == true)
    }

    @Test("AC-HOME-10 主数字滚动：一秒后今日已倒贴增加 0.0397")
    func headlineRolls() throws {
        let state = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let headline = { (now: Moment) -> String? in
            guard case .unpaidWork(let body) = snapshot(of: state, at: now).panel?.body else { return nil }
            return body.headline
        }

        // 3913 秒 × 1000 ÷ 25200 = 155.2778
        #expect(headline(standardDay(19, 5, 12)) == "¥155.2381")
        #expect(headline(standardDay(19, 5, 13)) == "¥155.2778")
    }

    @Test("F4 周六被迫营业计时中同白干计时中：今日结算为 0")
    func forcedOnRestDayPanel() throws {
        let saturday = { (hour: Int, minute: Int) in moment(2026, 2, 14, hour, minute) }
        let state = try applied(.startUnpaidWork, to: try onboarded(), at: saturday(10, 0))
        let panel = try #require(snapshot(of: state, at: saturday(10, 30)).panel)

        #expect(panel.statusLabel == "白干中")
        #expect(panel.body == .unpaidWork(UnpaidWorkPanel(
            label: "今日已倒贴",
            headline: "¥71.4286",
            caption: "10:00 起 · 已白干 0:30:00",
            stats: [
                StatItem(title: "今日结算", value: "¥0"),
                StatItem(title: "距离周末", value: "正在休息", isHighlighted: true),
                StatItem(title: "本月累计", value: "¥10000"),
            ],
            isRestDay: true
        )))
    }

    @Test("AC-BAR-09 白干计时中小牛边拉磨边冒汗，菜单栏数字仍是今日结算；停止后回到躺平")
    func cowSweats() throws {
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let stopped = try applied(.stopUnpaidWork, to: running, at: standardDay(19, 0))

        #expect(snapshot(of: running, at: standardDay(18, 30)).menuBar == MenuBarDisplay(pose: .sweating, text: "1000.0000"))
        #expect(snapshot(of: stopped, at: standardDay(19, 30)).menuBar == MenuBarDisplay(pose: .lyingFlat, text: "1000.0000"))
    }

    @Test("AC-HOME-05 没有白干记录时已下班小字仍为【准点下班，赢】")
    func noRecordsMeansOnTime() throws {
        #expect(try attendancePanel(try onboarded(), at: standardDay(18, 30)).caption == "准点下班，赢")
    }

    @Test("白干段重启后保留：状态存成 JSON 再读回，快照不变")
    func survivesRestart() throws {
        let state = try unpaidWork(try onboarded(), from: standardDay(18, 0), to: standardDay(19, 30))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(snapshot(of: restored, at: standardDay(20, 0)) == snapshot(of: state, at: standardDay(20, 0)))
    }
}

@Suite("白干计时：读回状态")
struct UnpaidWorkPersistenceTests {
    @Test("没有日记录的旧状态文件照常读入：今天没有白干记录")
    func oldFileWithoutDayRecords() throws {
        let running = try apply(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0)).state
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(running)) as? [String: Any])
        json["dayRecords"] = nil
        let old = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
        let today = try #require(snapshot(of: old, at: standardDay(18, 30)).today)

        #expect(today.unpaidWork.hasRecords == false)
        #expect(try attendancePanel(old, at: standardDay(18, 30)).caption == "准点下班，赢")
    }
}

@Suite("白干计时：节假日、请假、扣钱、作息")
struct UnpaidWorkWithDayRecordsTests {
    /// 2026 年春节：2 月 15 日至 23 日放假，2 月 14 日、28 日周六调休上班；2 月应出勤 16 天，日薪 1250。
    private let springFestival = HolidayTable(
        days: Dictionary(uniqueKeysWithValues:
            (15...23).map { (LocalDate(year: 2026, month: 2, day: $0), HolidayKind.holiday) }
            + [14, 28].map { (LocalDate(year: 2026, month: 2, day: $0), HolidayKind.makeupDay) }
        )
    )

    @Test("PRD 4.4.3 #1 被迫营业按节假日表判定：春节放假的周一是休息日，可以被迫营业；时薪按当月日薪 1250 ÷ 7")
    func forcedOnStatutoryHoliday() throws {
        let monday = { (hour: Int) in moment(2026, 2, 16, hour, 0) }
        let state = try onboarded()

        #expect(snapshot(of: state, at: monday(10), holidays: springFestival).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "被迫营业", command: .startUnpaidWork))
        let running = try apply(.startUnpaidWork, to: state, at: monday(10), holidays: springFestival).state
        let today = try #require(snapshot(of: running, at: monday(11), holidays: springFestival).today)
        #expect(today.status == .restDay)
        #expect(today.unpaidWork.isRunning)
        // 1250 ÷ 7 = 178.5714
        #expect(rounded4(today.unpaidWork.owed) == Decimal(string: "178.5714")!)
    }

    @Test("PRD 4.4.3 #1 调休上班的周六按应出勤日：上班中不能被迫营业，已下班才是「我还没走」")
    func makeupSaturdayIsAttendance() throws {
        let saturday = { (hour: Int) in moment(2026, 2, 14, hour, 0) }
        let state = try onboarded()

        #expect(snapshot(of: state, at: saturday(15), holidays: springFestival).panel?.unpaidWorkButton == nil)
        #expect(throws: CommandError.unpaidWorkUnavailable) {
            try apply(.startUnpaidWork, to: state, at: saturday(15), holidays: springFestival)
        }
        #expect(snapshot(of: state, at: saturday(19), holidays: springFestival).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "我还没走", command: .startUnpaidWork))
    }

    @Test("全天请假按休息日呈现，可以被迫营业；白干中统计行带今日结算、距离周末、本月累计")
    func forcedOnFullDayLeave() throws {
        let state = try onLeave(fullDayLeave(100))

        #expect(snapshot(of: state, at: standardDay(10, 0)).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "被迫营业", command: .startUnpaidWork))
        let running = try applied(.startUnpaidWork, to: state, at: standardDay(10, 0))
        let panel = try #require(snapshot(of: running, at: standardDay(10, 30)).panel)
        #expect(panel.statusLabel == "白干中")
        #expect(panel.body == .unpaidWork(UnpaidWorkPanel(
            label: "今日已倒贴",
            headline: "¥71.4286",
            caption: "10:00 起 · 已白干 0:30:00",
            stats: [
                StatItem(title: "今日结算", value: "¥0"),
                StatItem(title: "距离周末", value: "3 天", isHighlighted: true),
                StatItem(title: "本月累计", value: "¥7000"),
            ],
            isRestDay: true
        )))
    }

    @Test("AC-HOME-10 有扣款时白干中统计行为今日结算、距离周末、本月累计；白干不改变扣款后的结算")
    func runningStatsIncludeDeduction() throws {
        let fined = try recordingDeduction(.fixed(50), on: try onboarded(), at: standardDay(15, 0))
        let running = try applied(.startUnpaidWork, to: fined, at: standardDay(18, 0))
        guard case .unpaidWork(let body) = snapshot(of: running, at: standardDay(18, 30)).panel?.body else {
            Issue.record("期望白干中面板")
            return
        }

        #expect(body.stats == [
            StatItem(title: "今日结算", value: "¥950"),
            StatItem(title: "距离周末", value: "3 天", isHighlighted: true),
            StatItem(title: "本月累计", value: "¥7950"),
        ])
    }

    @Test("PRD 4.4.3 #4 请假不影响时薪：请前半天后白干 1 小时仍倒贴 ¥142.86；撤销请假后白干段仍在")
    func halfDayLeaveKeepsHourlyWageAndRecord() throws {
        let worked = try unpaidWork(try onLeave(firstHalfLeave(50)), from: standardDay(18, 0), to: standardDay(19, 0))
        let cancelled = try applied(.cancelLeave, to: worked, at: standardDay(19, 10))

        // 请了半天，扣款并在小字末尾。
        #expect(try attendancePanel(worked, at: standardDay(19, 5)).caption.hasPrefix("今日白干 1:00 · 倒贴 ¥142.86 · 扣款 "))
        #expect(try attendancePanel(cancelled, at: standardDay(19, 30)).caption == "今日白干 1:00 · 倒贴 ¥142.86")
    }

    @Test("PRD 4.2.3 #2 今天改了作息：时薪按今天生效的作息算，默认作息 8 小时，白干 1 小时倒贴 ¥125")
    func scheduleChangedToday() throws {
        let changed = try applied(.changeSchedule(.default), to: try onboarded(), at: standardDay(18, 10))
        let state = try unpaidWork(changed, from: standardDay(18, 30), to: standardDay(19, 30))

        #expect(try attendancePanel(state, at: standardDay(19, 30)).caption == "今日白干 1:00 · 倒贴 ¥125")
    }
}
