import Foundation
import Testing
import WageCore

// 历史月列表与日历 (PRD 4.6.1、F10、F11)，只读部分。
// 标准算例：2026 年 2 月只按双休 20 个应出勤日，月薪 20000，日薪 1000，作息 10:00 至 18:00。

/// 在 `now` 时刻执行一条命令，返回新状态。
private func applied(_ command: Command, to state: AppState, at now: Moment) throws -> AppState {
    try apply(command, to: state, at: now).state
}

private let february = YearMonth(year: 2026, month: 2)

private let lateFifty = Command.addDeduction(DeductionInput(amount: .fixed(50), reason: .late, note: ""))

/// 2 月的一串情绪记录：2 月 2 日 (周一) 安装，4 日迟到扣 50，6 日请后半天 13:00 至 18:00 (50%)，9 日 18:00 至 19:30 白干。
private func februaryWithRecords() throws -> AppState {
    var state = try onboarded(at: moment(2026, 2, 2, 9, 0))
    state = try applied(lateFifty, to: state, at: moment(2026, 2, 4, 15, 0))
    state = try applied(.setLeave(secondHalfLeave(50)), to: state, at: moment(2026, 2, 6, 9, 0))
    state = try applied(.startUnpaidWork, to: state, at: moment(2026, 2, 9, 18, 0))
    return try applied(.stopUnpaidWork, to: state, at: moment(2026, 2, 9, 19, 30))
}

/// 月列表里某个月的汇总。
private func summary(_ snap: Snapshot, _ month: YearMonth) throws -> HistoryMonthSummary {
    try #require(snap.historyMonths().first { $0.month == month })
}

@Suite("历史：月列表")
struct HistoryMonthListTests {
    @Test("AC-PRE-02 2 月 11 日安装，4 月打开月列表：按月倒序 4 月、3 月、2 月，最早一个月为安装当月")
    func startsFromInstallMonth() throws {
        let snap = snapshot(of: try onboarded(), at: moment(2026, 4, 15, 15, 0))

        #expect(snap.historyMonths().map(\.title) == ["2026年4月", "2026年3月", "2026年2月"])
        #expect(snap.historyMonths().map(\.isCurrentMonth) == [true, false, false])
        #expect(snap.historyMonths().map(\.badge) == ["本月 · 进行中", nil, "安装当月"])
    }

    @Test("未完成引导时没有历史")
    func emptyBeforeOnboarding() {
        #expect(snapshot(of: AppState(), at: standardDay(15, 0)).historyMonths().isEmpty)
    }
}

@Suite("历史：月汇总")
struct HistoryMonthSummaryTests {
    @Test("AC-HIS-01 PRD 4.3.4 本月累计算例：前 9 个应出勤日满勤，今天 15:00 记扣钱 50，本月结算总额 ¥9542.8571，与面板本月累计一致")
    func currentMonthMatchesMonthToDate() throws {
        // 2026-02-13 周五是 2 月第 10 个应出勤日。
        let now = moment(2026, 2, 13, 15, 0)
        let state = try applied(lateFifty, to: try onboarded(), at: now)
        let snap = snapshot(of: state, at: now)
        let panelMonthToDate = try attendancePanel(state, at: now).stats.first { $0.title == "本月累计" }

        #expect(try summary(snap, february).total == "¥9542.86")
        #expect(panelMonthToDate?.value == "¥9542.86")
    }

    @Test("AC-HIS-02 3 月查看 2 月：结算总额 20000 - 50 - 500 = ¥19450，应出勤 20 天，扣款 ¥550，请假 0.71 天，白干 1h30m")
    func pastMonthSummary() throws {
        let summary = try summary(snapshot(of: try februaryWithRecords(), at: moment(2026, 3, 10, 15, 0)), february)

        #expect(summary.total == "¥19450")
        #expect(summary.figures.map(\.value) == ["20 天", "¥550", "0.71 天", "1h30m"])
    }

    @Test("AC-HIS-03 某月请了一次前半天 (2 小时工时，标准工时 7 小时)：请假天数 0.29")
    func partialLeaveCountsByWorkShare() throws {
        let state = try applied(
            .setLeave(firstHalfLeave(50)), to: try onboarded(), at: standardDay(9, 0)
        )
        let summary = try summary(snapshot(of: state, at: standardDay(20, 0)), february)

        #expect(summary.leave.value == "0.29 天")
    }

    @Test("一整天假计 1 天；没有扣款和白干时扣款合计 ¥0、白干时长 0:00")
    func fullDayLeaveCountsOne() throws {
        let state = try applied(
            .setLeave(fullDayLeave(0)), to: try onboarded(), at: standardDay(9, 0)
        )
        let summary = try summary(snapshot(of: state, at: moment(2026, 3, 2, 9, 0)), february)

        #expect([summary.total] + summary.figures.map(\.value) == ["¥20000", "20 天", "¥0", "1 天", "0m"])
    }

    @Test("本月的扣款合计、请假天数与结算总额同口径，只算到今天：系统时间拨回到请假那天之前，未来那天的请假不计入")
    func currentMonthCountsUpToToday() throws {
        let leave = Command.setLeave(fullDayLeave(100))
        let state = try applied(leave, to: try onboarded(), at: moment(2026, 2, 13, 9, 0))
        let snap = snapshot(of: state, at: standardDay(15, 0))

        #expect(try [summary(snap, february).total] + summary(snap, february).figures.map(\.value) == ["¥7571.43", "20 天", "¥0", "0 天", "0m"])
        #expect(try day(snap, feb(13)).kind == .leave)
    }

    @Test("应出勤日数按节假日表：2026 年 10 月国庆放假、10 日调休上班，应出勤 18 天")
    func attendanceDaysFollowHolidays() throws {
        let snap = snapshot(of: try onboarded(at: moment(2026, 10, 9, 9, 0)), at: moment(2026, 10, 9, 15, 0), holidays: nationalDay2026)

        #expect(try summary(snap, YearMonth(year: 2026, month: 10)).attendance == HistoryFigure(title: "应出勤", value: "18 天"))
    }
}

/// 月日历里的某一天。
private func day(_ snap: Snapshot, _ date: LocalDate) throws -> HistoryDay {
    let month = try #require(snap.historyMonth(date.yearMonth))
    return try #require(month.days.first { $0.date == date })
}

private func feb(_ day: Int) -> LocalDate {
    LocalDate(year: 2026, month: 2, day: day)
}

@Suite("历史：月日历")
struct HistoryCalendarTests {
    @Test("PRD 4.6.1 颜色类型：满勤、被扣钱、请假、休息日；今天另外标出，不遮住当天的类型；未来的应出勤日为未到")
    func dayKinds() throws {
        let snap = snapshot(of: try februaryWithRecords(), at: moment(2026, 2, 11, 15, 0))
        let kinds = try [3, 4, 6, 7, 9, 11, 12].map { try day(snap, feb($0)).kind }

        #expect(kinds == [.fullAttendance, .deducted, .leave, .rest, .fullAttendance, .fullAttendance, .upcoming])
        #expect(try [10, 11, 12].map { try day(snap, feb($0)).isToday } == [false, true, false])
        #expect(CalendarDayKind.allCases.map(\.label) == ["满勤", "被扣钱", "请假", "休息日", "改成不上班", "未到"])
        #expect(CalendarDayKind.legend.map(\.label) == ["满勤", "被扣钱", "请假", "改成不上班"])
        #expect(CalendarDayKind.todayLabel == "今天")
    }

    @Test("日历按周一至周日排：2026 年 2 月 1 日是周日，前面空 6 格，共 28 天，月汇总与月列表一致")
    func layout() throws {
        let snap = snapshot(of: try februaryWithRecords(), at: moment(2026, 3, 10, 15, 0))
        let month = try #require(snap.historyMonth(february))

        #expect(month.leadingBlanks == 6)
        #expect(month.days.map(\.dayText) == (1...28).map(String.init))
        #expect(month.summary == (try summary(snap, february)))
    }

    @Test("安装当月之前和本月之后的月份没有日历")
    func outOfRange() throws {
        let snap = snapshot(of: try onboarded(), at: moment(2026, 3, 10, 15, 0))

        #expect(snap.historyMonth(YearMonth(year: 2026, month: 1)) == nil)
        #expect(snap.historyMonth(YearMonth(year: 2026, month: 4)) == nil)
        #expect(snap.historyMonth(YearMonth(year: 2026, month: 3)) != nil)
    }

    @Test("AC-PRE-01 2 月 11 日安装：此前已过的 7 个应出勤日均为满勤，各结算 ¥1000")
    func daysBeforeInstallAreFull() throws {
        let snap = snapshot(of: try onboarded(), at: standardDay(15, 0))
        let days = try [2, 3, 4, 5, 6, 9, 10].map { try day(snap, feb($0)) }

        #expect(days.allSatisfy { $0.kind == .fullAttendance })
        #expect(days.allSatisfy { $0.detail.stats == [StatItem(title: "当天结算", value: "¥1000")] })
    }
}

@Suite("历史：单日详情")
struct HistoryDayDetailTests {
    @Test("被扣钱的一天：结算 ¥950，扣款明细迟到 −¥50，判定来源工作日")
    func deductedDay() throws {
        let detail = try day(snapshot(of: try februaryWithRecords(), at: moment(2026, 3, 10, 15, 0)), feb(4)).detail

        #expect(detail.title == "2月4日 周三")
        #expect(detail.source == .workday)
        #expect(detail.source.label == "工作日")
        #expect(detail.sourceItem == StatItem(title: "判定来源", value: "工作日"))
        #expect(detail.stats == [StatItem(title: "当天结算", value: "¥950")])
        #expect(detail.deductions.map(\.title) == ["迟到"])
        #expect(detail.deductions.map(\.amount) == ["−¥50"])
        #expect(detail.leave == nil)
        #expect(detail.unpaidWork.isEmpty)
        #expect(detail.editing.unpaidWorkItems.isEmpty)
    }

    @Test("请后半天的一天：请假 13:00–18:00 · 扣薪 50% −¥500，结算 ¥500")
    func leaveDay() throws {
        let detail = try day(snapshot(of: try februaryWithRecords(), at: moment(2026, 3, 10, 15, 0)), feb(6)).detail

        #expect(detail.leave == HistoryLine(title: "请假 13:00–18:00", detail: "扣薪 50.00%", value: "−¥500"))
        #expect(detail.stats == [StatItem(title: "当天结算", value: "¥500")])
    }

    @Test("有白干的一天：白干段 18:00 – 19:30 共 1h30m，白干 1:30 · 倒贴 ¥214.2857，结算仍是 ¥1000")
    func unpaidWorkDay() throws {
        let detail = try day(snapshot(of: try februaryWithRecords(), at: moment(2026, 3, 10, 15, 0)), feb(9)).detail

        #expect(detail.unpaidWork == [HistoryLine(title: "18:00 – 19:30", detail: nil, value: "1h30m")])
        #expect(detail.editing.unpaidWorkItems.map(\.loss) == ["倒贴 ¥214.29"])
        #expect(detail.stats == [StatItem(title: "当天结算", value: "¥1000")])
    }

    @Test("PRD 4.3.5 #12 可能忘了停：周一 18:00 开始忘了停，周二 10:00 计划上班时自动停止，详情写「次日 10:00」并标出")
    func autoStopped() throws {
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: moment(2026, 2, 9, 18, 0))
        let now = moment(2026, 2, 10, 10, 30)
        let advanced = try applied(.advance, to: running, at: now)
        let expected = [HistoryLine(title: "18:00 – 次日 10:00", detail: "可能忘了停", value: "16h00m")]

        #expect(try day(snapshot(of: advanced, at: now), feb(9)).detail.unpaidWork == expected)
        // 还没推进时按已在计划上班自动停止推导，与推进后一致。
        #expect(try day(snapshot(of: running, at: now), feb(9)).detail.unpaidWork == expected)
        // 自动停止之前，跨过零点也还在计时，详情写计时中。
        #expect(try day(snapshot(of: running, at: moment(2026, 2, 10, 0, 30)), feb(9)).detail.unpaidWork
            == [HistoryLine(title: "18:00 起", detail: "计时中", value: "6h30m")])
    }

    @Test("今天计时中的白干段：18:00 起 · 计时中，时长算到此刻")
    func runningSegment() throws {
        let running = try applied(.startUnpaidWork, to: try onboarded(), at: standardDay(18, 0))
        let detail = try day(snapshot(of: running, at: standardDay(19, 0)), feb(11)).detail

        #expect(detail.unpaidWork == [HistoryLine(title: "18:00 起", detail: "计时中", value: "1h00m")])
    }

    @Test("今天还没结算：显示今日已赚与今日上限；未来的应出勤日显示预计结算")
    func todayAndFuture() throws {
        let snap = snapshot(of: try onboarded(), at: standardDay(15, 0))

        #expect(try day(snap, feb(11)).detail.stats == [
            StatItem(title: "今日已赚", value: "¥571.43"),
            StatItem(title: "今日上限", value: "¥1000"),
        ])
        #expect(try day(snap, feb(12)).detail.stats == [StatItem(title: "预计结算", value: "¥1000")])
    }

    @Test("休息日没有收入：没有结算项，判定来源双休")
    func restDay() throws {
        let detail = try day(snapshot(of: try onboarded(), at: standardDay(15, 0)), feb(7)).detail

        #expect(detail.stats.isEmpty)
        #expect(detail.source == .weekend)
    }

    @Test("AC-CAL-06 打开国庆某天：判定来源法定节假日，休息日；调休上班的 10 月 10 日判定来源调休上班")
    func nationalDay() throws {
        let state = try onboarded(at: moment(2026, 10, 9, 9, 0))
        let snap = snapshot(of: state, at: moment(2026, 10, 20, 15, 0), holidays: nationalDay2026)
        let holiday = try day(snap, LocalDate(year: 2026, month: 10, day: 3))
        let makeup = try day(snap, LocalDate(year: 2026, month: 10, day: 10))

        #expect(holiday.detail.source.label == "法定节假日")
        #expect(holiday.kind == .rest)
        #expect(makeup.detail.source.label == "调休上班")
        #expect(makeup.kind == .fullAttendance)
    }
}

/// 2026 年国庆：10 月 1 日至 7 日放假，10 月 10 日周六调休上班。
private let nationalDay2026 = HolidayTable(
    days: Dictionary(uniqueKeysWithValues: (1...7).map { (LocalDate(year: 2026, month: 10, day: $0), HolidayKind.holiday) }
        + [(LocalDate(year: 2026, month: 10, day: 10), HolidayKind.makeupDay)])
)
