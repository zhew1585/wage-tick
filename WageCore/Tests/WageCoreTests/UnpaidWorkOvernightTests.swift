import Foundation
import Testing
import WageCore

// 白干跨过零点与自动停止 (PRD 4.4.3 #3、4.3.5 #12，V1.8)。
// 标准算例：日薪 1000，作息 10:00 至 18:00、饭点 12:00 至 13:00，标准工时 7 小时。
// 2026-02-11 是周三，13 日周五，14、15 日周末，16 日周一。

private func applied(_ command: Command, to state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> AppState {
    try apply(command, to: state, at: now, holidays: holidays).state
}

private func feb(_ day: Int) -> LocalDate {
    LocalDate(year: 2026, month: 2, day: day)
}

private func time(_ hour: Int, _ minute: Int) -> TimeOfDay {
    TimeOfDay(hour: hour, minute: minute)
}

/// 周三 18:00 点了「我还没走」一直没停。
private func runningSinceWednesday() throws -> AppState {
    try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
}

/// 某天在历史里的白干段。
private func unpaidLines(_ state: AppState, _ date: LocalDate, at now: Moment, holidays: HolidayTable = .empty) throws -> [HistoryLine] {
    try #require(snapshot(of: state, at: now, holidays: holidays).historyDay(date)).detail.unpaidWork
}

private func unpaidWorkBody(_ state: AppState, at now: Moment, holidays: HolidayTable = .empty) throws -> UnpaidWorkPanel {
    guard case .unpaidWork(let body) = try #require(snapshot(of: state, at: now, holidays: holidays).panel).body else {
        Issue.record("期望白干中面板")
        throw CancellationError()
    }
    return body
}

@Suite("白干跨过零点：面板与菜单栏")
struct UnpaidWorkPastMidnightPanelTests {
    @Test("周三 18:00 开始，周四 00:30 打开：仍是白干中，主数字是周三已倒贴 6.5 × 142.8571，统计行是周四未上班的")
    func runningPastMidnight() throws {
        let snap = snapshot(of: try runningSinceWednesday(), at: moment(2026, 2, 12, 0, 30))
        let panel = try #require(snap.panel)
        let today = try #require(snap.today)

        #expect(panel.statusLabel == "白干中")
        #expect(panel.unpaidWorkButton == UnpaidWorkButton(title: "终于下班了", command: .stopUnpaidWork))
        #expect(panel.body == .unpaidWork(UnpaidWorkPanel(
            label: "昨天已倒贴",
            headline: "¥928.5714",
            caption: "昨天 18:00 起 · 已白干 6:30:00",
            stats: [
                StatItem(title: "距离下班", value: "-"),
                StatItem(title: "距离周末", value: "2 天", tone: .accent),
                StatItem(title: "本月累计", value: "¥8000"),
            ],
            isRestDay: false
        )))
        #expect(snap.menuBar == MenuBarDisplay(pose: .sweating, text: "0.0000"))
        #expect(today.isRolling)
        #expect(today.unpaidWork.running?.date == feb(11))
        // 周四自己还没有白干，已倒贴都算在周三。
        #expect(today.unpaidWork.milliseconds == 0)
        #expect(!today.unpaidWork.hasRecords)
    }

    @Test("开始那天之前停过的段也算进主数字：18:00 至 18:30、19:00 起到次日 00:30，共 6 小时")
    func headlineIncludesEarlierSegments() throws {
        let first = try applied(.stopUnpaidWork, to: try runningSinceWednesday(), at: standardDay(18, 30))
        let running = try applied(.startUnpaidWork, to: first, at: standardDay(19, 0))
        let body = try unpaidWorkBody(running, at: moment(2026, 2, 12, 0, 30))

        #expect(body.headline == "¥857.1429")
        #expect(body.caption == "昨天 19:00 起 · 已白干 6:00:00")
    }

    @Test("周五开始一直到周日：标签与小字写开始那天的日期，统计行是周日休息日的")
    func runningIntoWeekend() throws {
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: moment(2026, 2, 13, 18, 0))
        let body = try unpaidWorkBody(running, at: moment(2026, 2, 15, 12, 0))

        #expect(body == UnpaidWorkPanel(
            label: "2月13日已倒贴",
            headline: "¥6000.0000",
            caption: "2月13日 18:00 起 · 已白干 42:00:00",
            stats: [
                StatItem(title: "本月已上班", value: "10/20 天"),
                StatItem(title: "本月累计", value: "¥10000"),
                StatItem(title: "距离周末", value: "正在休息", tone: .accent),
            ],
            isRestDay: true
        ))
    }

    @Test("零点后点「终于下班了」：那段留在周三，写「18:00 – 次日 00:30」；周四没有白干记录，未上班不能再开始")
    func stopAfterMidnight() throws {
        let stopped = try applied(.stopUnpaidWork, to: try runningSinceWednesday(), at: moment(2026, 2, 12, 0, 30))
        let now = moment(2026, 2, 12, 0, 40)
        let snap = snapshot(of: stopped, at: now)

        #expect(try unpaidLines(stopped, feb(11), at: now) == [HistoryLine(title: "18:00 – 次日 00:30", detail: nil, value: "6h30m")])
        #expect(snap.panel?.statusLabel == "未上班")
        #expect(snap.today?.unpaidWork.hasRecords == false)
        #expect(snap.panel?.unpaidWorkButton == nil)
    }
}

@Suite("白干自动停止：下一个应出勤日的计划上班")
struct UnpaidWorkAutoStopTests {
    @Test("AC-OT-05 周三开始不停止：周四 10:00 计划上班前一直计时，推进到 10:00 自动停止并标记可能忘了停")
    func stopsAtNextPlannedStart() throws {
        let running = try runningSinceWednesday()
        let before = try applied(.advance, to: running, at: moment(2026, 2, 12, 9, 59, 59))
        #expect(snapshot(of: before, at: moment(2026, 2, 12, 9, 59, 59)).today?.unpaidWork.isRunning == true)

        let now = moment(2026, 2, 12, 10, 0)
        let stopped = try applied(.advance, to: running, at: now)
        let snap = snapshot(of: stopped, at: now)
        #expect(snap.today?.unpaidWork.isRunning == false)
        #expect(snap.panel?.statusLabel == "上班中")
        #expect(snap.menuBar.pose == .grinding)
        #expect(try unpaidLines(stopped, feb(11), at: now)
            == [HistoryLine(title: "18:00 – 次日 10:00", detail: "可能忘了停", value: "16h00m")])
    }

    @Test("没推进时取快照也按已自动停止推导，与推进后的快照一致")
    func snapshotWithoutAdvanceMatches() throws {
        let running = try runningSinceWednesday()
        let now = moment(2026, 2, 12, 10, 30)

        #expect(snapshot(of: running, at: now) == snapshot(of: try applied(.advance, to: running, at: now), at: now))
    }

    @Test("周五开始：跳过周末，到周一 10:00 才自动停止，写「18:00 – 2月16日 10:00」")
    func skipsWeekend() throws {
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: moment(2026, 2, 13, 18, 0))
        #expect(snapshot(of: running, at: moment(2026, 2, 16, 9, 59)).today?.unpaidWork.isRunning == true)

        let now = moment(2026, 2, 16, 10, 30)
        let stopped = try applied(.advance, to: running, at: now)
        #expect(try unpaidLines(stopped, feb(13), at: now)
            == [HistoryLine(title: "18:00 – 2月16日 10:00", detail: "可能忘了停", value: "64h00m")])
    }

    /// 2026 年春节：2 月 15 日至 23 日放假，2 月 14 日周六调休上班。
    private let springFestival = HolidayTable(
        days: Dictionary(uniqueKeysWithValues:
            (15...23).map { (LocalDate(year: 2026, month: 2, day: $0), HolidayKind.holiday) }
            + [(LocalDate(year: 2026, month: 2, day: 14), HolidayKind.makeupDay)]
        )
    )

    @Test("按节假日表：周五开始停在调休上班的周六 10:00；调休周六开始跳过整个春节，停在 2 月 24 日 10:00")
    func followsHolidayTable() throws {
        let friday = try applied(.startUnpaidWork, to: try onboarded(), at: moment(2026, 2, 13, 18, 0), holidays: springFestival)
        let saturdayMorning = moment(2026, 2, 14, 10, 30)
        let stopped = try applied(.advance, to: friday, at: saturdayMorning, holidays: springFestival)
        #expect(try unpaidLines(stopped, feb(13), at: saturdayMorning, holidays: springFestival)
            == [HistoryLine(title: "18:00 – 次日 10:00", detail: "可能忘了停", value: "16h00m")])

        let saturday = try applied(.startUnpaidWork, to: try onboarded(), at: moment(2026, 2, 14, 18, 0), holidays: springFestival)
        #expect(snapshot(of: saturday, at: moment(2026, 2, 24, 9, 59), holidays: springFestival).today?.unpaidWork.isRunning == true)
        let now = moment(2026, 2, 25, 9, 0)
        #expect(try unpaidLines(saturday, feb(14), at: now, holidays: springFestival)
            == [HistoryLine(title: "18:00 – 2月24日 10:00", detail: "可能忘了停", value: "232h00m")])
    }

    @Test("次日请了前半天 (10:00 至 12:00)：停在请假后实际上班的 13:00 (饭点之后)")
    func nextDayLeaveAtBeginning() throws {
        let leave = try applied(.editDay(feb(12), .setLeave(firstHalfLeave(50))), to: try onboarded(), at: standardDay(15, 0))
        let running = try applied(.startUnpaidWork, to: leave, at: standardDay(18, 0))
        #expect(snapshot(of: running, at: moment(2026, 2, 12, 12, 59)).today?.unpaidWork.isRunning == true)

        let now = moment(2026, 2, 12, 13, 0)
        let stopped = try applied(.advance, to: running, at: now)
        #expect(try unpaidLines(stopped, feb(11), at: now)
            == [HistoryLine(title: "18:00 – 次日 13:00", detail: "可能忘了停", value: "19h00m")])
    }

    @Test("次日全天请假：跳过它，停在周五 10:00；周四白天面板仍是白干中，统计行是请假日的")
    func nextDayFullDayLeave() throws {
        let leave = try applied(.editDay(feb(12), .setLeave(fullDayLeave(100))), to: try onboarded(), at: standardDay(15, 0))
        let running = try applied(.startUnpaidWork, to: leave, at: standardDay(18, 0))
        let body = try unpaidWorkBody(running, at: moment(2026, 2, 12, 15, 0))
        #expect(body.label == "昨天已倒贴")
        #expect(body.isRestDay)
        #expect(body.stats.map(\.title) == ["本月已上班", "本月累计", "距离周末"])

        let now = moment(2026, 2, 13, 10, 0)
        let stopped = try applied(.advance, to: running, at: now)
        #expect(try unpaidLines(stopped, feb(11), at: now)
            == [HistoryLine(title: "18:00 – 2月13日 10:00", detail: "可能忘了停", value: "40h00m")])
    }

    @Test("往后 60 天都没有要上班的日子：在开始那天之后第 7 天的 0 点自动停止")
    func fallbackAfterSevenDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 2, day: 12))!
        let days = (0..<80).map { offset in
            let parts = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: .day, value: offset, to: first)!)
            return (LocalDate(year: parts.year!, month: parts.month!, day: parts.day!), HolidayKind.holiday)
        }
        let longBreak = HolidayTable(days: Dictionary(uniqueKeysWithValues: days))
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0), holidays: longBreak)
        let now = moment(2026, 2, 20, 12, 0)
        let stopped = try applied(.advance, to: running, at: now, holidays: longBreak)

        #expect(try unpaidLines(stopped, feb(11), at: now, holidays: longBreak)
            == [HistoryLine(title: "18:00 – 2月18日 00:00", detail: "可能忘了停", value: "150h00m")])
    }
}

@Suite("白干开始：不再受零点限制")
struct UnpaidWorkStartNearMidnightTests {
    @Test("PRD 4.4.3 #1 已下班的 23:59:30 仍可开始，过了零点照样计时")
    func startJustBeforeMidnight() throws {
        let lastMinute = standardDay(23, 59, 30)
        #expect(snapshot(of: try onboarded(), at: lastMinute).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "我还没走", command: .startUnpaidWork))

        let running = try applied(.startUnpaidWork, to: try onboarded(), at: lastMinute)
        let body = try unpaidWorkBody(running, at: moment(2026, 2, 12, 0, 10))
        #expect(body.caption == "昨天 23:59 起 · 已白干 0:10:30")
    }

    @Test("休息日的 23:59:59 仍可被迫营业")
    func restDayJustBeforeMidnight() throws {
        #expect(snapshot(of: try onboarded(), at: moment(2026, 2, 14, 23, 59, 59)).panel?.unpaidWorkButton
            == UnpaidWorkButton(title: "被迫营业", command: .startUnpaidWork))
    }
}

@Suite("白干跨过零点：读回状态")
struct UnpaidWorkLegacyDecodingTests {
    @Test("V1.8 之前的文件用 suspectedAllNighter 记标记：读回为可能忘了停，再存时写成 autoStopped")
    func decodesSuspectedAllNighter() throws {
        let stopped = try applied(.advance, to: try runningSinceWednesday(), at: moment(2026, 2, 12, 10, 30))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(stopped)) as? [String: Any])
        var records = try #require(json["dayRecords"] as? [[String: Any]])
        var segments = try #require(records[0]["unpaidWork"] as? [[String: Any]])
        #expect(segments[0]["autoStopped"] as? Bool == true)
        segments[0]["autoStopped"] = nil
        segments[0]["suspectedAllNighter"] = true
        records[0]["unpaidWork"] = segments
        json["dayRecords"] = records
        let old = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(old == stopped)
        let resaved = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        let resavedSegment = try #require(((resaved["dayRecords"] as? [[String: Any]])?[0]["unpaidWork"] as? [[String: Any]])?[0])
        #expect(resavedSegment["autoStopped"] as? Bool == true)
        #expect(resavedSegment["suspectedAllNighter"] == nil)
    }

    @Test("两个键都没有的段读回为没有标记")
    func missingFlagMeansNotAutoStopped() throws {
        let worked = try applied(.stopUnpaidWork, to: try runningSinceWednesday(), at: standardDay(19, 0))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(worked)) as? [String: Any])
        var records = try #require(json["dayRecords"] as? [[String: Any]])
        var segments = try #require(records[0]["unpaidWork"] as? [[String: Any]])
        segments[0]["autoStopped"] = nil
        records[0]["unpaidWork"] = segments
        json["dayRecords"] = records

        #expect(try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json)) == worked)
    }
}

@Suite("历史编辑：跨过零点的白干段")
struct UnpaidWorkOvernightEditTests {
    /// 2 月 2 日 (周一) 完成引导，此刻是 2 月 11 日 15:00。
    private func installed() throws -> AppState {
        try onboarded(at: moment(2026, 2, 2, 9, 0))
    }

    private func editing(_ date: LocalDate, _ edit: DayEdit, in state: AppState) throws -> AppState {
        try applied(.editDay(date, edit), to: state, at: standardDay(15, 0))
    }

    private func rejection(_ date: LocalDate, _ edit: DayEdit, in state: AppState) -> CommandError? {
        do throws(CommandError) {
            _ = try apply(.editDay(date, edit), to: state, at: standardDay(15, 0))
            return nil
        } catch {
            return error
        }
    }

    private func detail(_ state: AppState, _ date: LocalDate) throws -> HistoryDayDetail {
        try #require(snapshot(of: state, at: standardDay(15, 0)).historyDay(date)).detail
    }

    private let overnight = UnpaidWorkInput(start: time(23, 0), end: time(1, 30), endDayOffset: 1)

    @Test("补记周一 23:00 到次日 01:30：写「23:00 – 次日 01:30」，2h30m，倒贴 ¥357.14")
    func backfillOvernight() throws {
        let state = try editing(feb(9), .addUnpaidWork(overnight), in: try installed())
        let day = try detail(state, feb(9))

        #expect(day.unpaidWork == [HistoryLine(title: "23:00 – 次日 01:30", detail: nil, value: "2h30m")])
        #expect(day.editing.unpaidWorkItems.map(\.loss) == ["倒贴 ¥357.14"])
        #expect(day.editing.unpaidWorkItems.map(\.input) == [overnight])
        #expect(try detail(state, feb(10)).unpaidWork.isEmpty)
    }

    @Test("结束最晚到次日计划上班 10:00：正好 10:00 可以，10:30 被拒")
    func endBoundedByAutoStop() throws {
        let atBound = UnpaidWorkInput(start: time(23, 0), end: time(10, 0), endDayOffset: 1)
        let beyond = UnpaidWorkInput(start: time(23, 0), end: time(10, 30), endDayOffset: 1)

        #expect(throws: Never.self) { try editing(feb(9), .addUnpaidWork(atBound), in: try installed()) }
        #expect(rejection(feb(9), .addUnpaidWork(beyond), in: try installed()) == .unpaidWorkBeyondAutoStop)
        #expect(CommandError.unpaidWorkBeyondAutoStop.message == "结束不能晚于下一个上班日的上班时间")
    }

    @Test("跨过零点的段与次日的段也不能重叠")
    func overlapAcrossMidnight() throws {
        let state = try editing(feb(9), .addUnpaidWork(overnight), in: try installed())

        #expect(rejection(feb(10), .addUnpaidWork(UnpaidWorkInput(start: time(1, 0), end: time(2, 0))), in: state) == .unpaidWorkOverlap)
        #expect(throws: Never.self) {
            try editing(feb(10), .addUnpaidWork(UnpaidWorkInput(start: time(1, 30), end: time(2, 0))), in: state)
        }
    }

    @Test("结束日期的选项：周五为当天、次日、周日、周一 (到下周一计划上班自动停止)")
    func endDayOptions() throws {
        let options = try detail(try installed(), feb(6)).editing.unpaidWorkEndDays

        #expect(options.map(\.label) == ["当天", "次日", "2月8日 周日", "2月9日 周一"])
        #expect(options.map(\.offset) == [0, 1, 2, 3])
    }

    @Test("被自动停止的周五那段：修改预填结束为周一 10:00 (第 3 天)，改到当天 21:00 后不再标记")
    func editAutoStoppedWeekendSegment() throws {
        let running = try applied(.startUnpaidWork, to: try installed(), at: moment(2026, 2, 6, 18, 0))
        let stopped = try applied(.advance, to: running, at: moment(2026, 2, 9, 10, 30))
        let item = try #require(try detail(stopped, feb(6)).editing.unpaidWorkItems.first)

        #expect(item.line == HistoryLine(title: "18:00 – 2月9日 10:00", detail: "可能忘了停", value: "64h00m"))
        #expect(item.input == UnpaidWorkInput(start: time(18, 0), end: time(10, 0), endDayOffset: 3))
        let edited = try editing(feb(6), .editUnpaidWork(index: 0, UnpaidWorkInput(start: time(18, 0), end: time(21, 0))), in: stopped)
        #expect(try detail(edited, feb(6)).unpaidWork == [HistoryLine(title: "18:00 – 21:00", detail: nil, value: "3h00m")])
    }

    @Test("补记预填为计划下班起 1 小时：作息 16:00 至 23:30 时为 23:30 到次日 00:30")
    func draftCrossesMidnight() throws {
        let late = WorkSchedule(start: time(16, 0), end: time(23, 30), lunch: nil)
        let state = try onboarded(schedule: late, at: moment(2026, 2, 2, 9, 0))

        #expect(try detail(state, feb(9)).editing.unpaidWork
            == .available(UnpaidWorkInput(start: time(23, 30), end: time(0, 30), endDayOffset: 1)))
    }
}

@Suite("白干跨过零点：月汇总")
struct UnpaidWorkOvernightLedgerTests {
    @Test("1 月 31 日 (周六) 22:00 被迫营业到 2 月 1 日 01:00：3 小时全算在 1 月，2 月白干为 0")
    func attributedToStartDay() throws {
        let installed = try onboarded(at: moment(2026, 1, 5, 9, 0))
        let running = try applied(.startUnpaidWork, to: installed, at: moment(2026, 1, 31, 22, 0))
        let state = try applied(.stopUnpaidWork, to: running, at: moment(2026, 2, 1, 1, 0))
        let snap = snapshot(of: state, at: standardDay(15, 0))
        let months = snap.historyMonths()

        #expect(months.first { $0.month == YearMonth(year: 2026, month: 1) }?.unpaidWork.value == "3h00m")
        #expect(months.first { $0.month == YearMonth(year: 2026, month: 2) }?.unpaidWork.value == "0m")
        #expect(snap.historyDay(LocalDate(year: 2026, month: 1, day: 31))?.detail.unpaidWork
            == [HistoryLine(title: "22:00 – 次日 01:00", detail: nil, value: "3h00m")])
        #expect(snap.historyDay(feb(1))?.detail.unpaidWork.isEmpty == true)
    }
}
