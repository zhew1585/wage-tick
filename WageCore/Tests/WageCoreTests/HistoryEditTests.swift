import Foundation
import Testing
import WageCore

// 历史编辑与单日覆盖 (PRD 4.2.1、4.2.2、4.6.1、F11，issue #15)。
// 标准算例：2026 年 2 月只按双休 20 个应出勤日，月薪 20000，日薪 1000，作息 10:00 至 18:00。
// 「今天」是 2 月 11 日 (周三)：上周三是 2 月 4 日，下周三是 2 月 18 日，2 月 7 日是周六。

private func feb(_ day: Int) -> LocalDate {
    LocalDate(year: 2026, month: 2, day: day)
}

private let february = YearMonth(year: 2026, month: 2)

/// 2 月 2 日 (周一) 完成引导的标准算例。
private func installedFebruary2() throws -> AppState {
    try onboarded(at: moment(2026, 2, 2, 9, 0))
}

/// 在 `now` 时刻编辑 `date` 这一天，返回新状态。
private func editing(
    _ date: LocalDate, _ edit: DayEdit, in state: AppState, at now: Moment = standardDay(15, 0),
    holidays: HolidayTable = .empty
) throws -> AppState {
    try apply(.editDay(date, edit), to: state, at: now, holidays: holidays).state
}

/// 编辑被拒绝时的错误；没被拒绝时测试失败。
private func rejection(
    _ date: LocalDate, _ edit: DayEdit, in state: AppState, at now: Moment = standardDay(15, 0)
) throws -> CommandError? {
    do throws(CommandError) {
        _ = try apply(.editDay(date, edit), to: state, at: now)
        Issue.record("期望被拒绝")
        return nil
    } catch {
        return error
    }
}

/// 某天的历史详情。
private func detail(_ state: AppState, _ date: LocalDate, at now: Moment = standardDay(15, 0), holidays: HolidayTable = .empty) throws -> HistoryDayDetail {
    try #require(snapshot(of: state, at: now, holidays: holidays).historyDay(date)).detail
}

/// 某月的汇总项，按标题取值。
private func monthStat(_ state: AppState, _ month: YearMonth, _ title: String, at now: Moment = standardDay(15, 0)) throws -> String? {
    try #require(snapshot(of: state, at: now).historyMonth(month)).summary.stats.first { $0.title == title }?.value
}

private let fifty = DeductionInput(amount: .fixed(50), reason: .late, note: "")

@Suite("历史编辑：单日覆盖")
struct OverrideTests {
    @Test("AC-CAL-01 把周六 2 月 7 日改成上班日：本月应出勤日 21，各满勤日结算变为 952.381")
    func saturdayBecomesWorkday() throws {
        let state = try editing(feb(7), .setOverride(.workday), in: try installedFebruary2())
        let snap = snapshot(of: state, at: standardDay(15, 0))
        let saturday = try #require(snap.historyDay(feb(7)))

        #expect(try monthStat(state, february, "应出勤日数") == "21 天")
        #expect(try detail(state, feb(9)).stats == [StatItem(title: "结算", value: "¥952.381")])
        #expect(saturday.detail.stats == [StatItem(title: "结算", value: "¥952.381")])
        #expect(saturday.kind == .override)
        #expect(saturday.detail.source == .override)
        #expect(saturday.detail.sourceItem == StatItem(title: "判定来源", value: "单日覆盖"))
        #expect(snap.today?.dailyWage == Decimal(20000) / 21)
    }

    @Test("AC-CAL-02 撤销上一条覆盖：恢复为 20 天、1000")
    func undo() throws {
        let overridden = try editing(feb(7), .setOverride(.workday), in: try installedFebruary2())
        let state = try editing(feb(7), .clearOverride, in: overridden)

        #expect(try monthStat(state, february, "应出勤日数") == "20 天")
        #expect(try detail(state, feb(9)).stats == [StatItem(title: "结算", value: "¥1000")])
        #expect(try detail(state, feb(7)).source == .weekend)
        #expect(state == (try installedFebruary2()))
    }

    @Test("PRD 4.2.2 单日覆盖优先于调休与法定节假日：把国庆 10 月 2 日改成上班日、调休的 10 月 10 日改成不上班日")
    func beatsHolidayTable() throws {
        let now = moment(2026, 10, 20, 15, 0)
        var state = try onboarded(at: moment(2026, 10, 9, 9, 0))
        state = try editing(LocalDate(year: 2026, month: 10, day: 2), .setOverride(.workday), in: state, at: now, holidays: nationalDay2026)
        state = try editing(LocalDate(year: 2026, month: 10, day: 10), .setOverride(.dayOff), in: state, at: now, holidays: nationalDay2026)
        let snap = snapshot(of: state, at: now, holidays: nationalDay2026)
        let holiday = try #require(snap.historyDay(LocalDate(year: 2026, month: 10, day: 2)))
        let makeup = try #require(snap.historyDay(LocalDate(year: 2026, month: 10, day: 10)))

        #expect(holiday.detail.source == .override)
        #expect(holiday.kind == .override)
        #expect(holiday.detail.stats == [StatItem(title: "结算", value: "¥1111.1111")])
        #expect(makeup.detail.source == .override)
        #expect(makeup.detail.stats.isEmpty)
        // 18 天 + 1 - 1，日薪 20000 ÷ 18。
        #expect(try #require(snap.historyMonth(YearMonth(year: 2026, month: 10))).summary.stats[1].value == "18 天")
    }

    @Test("PRD 4.3.5 #18 上班中途把今天改成不上班日：状态立即变为休息日，本月累计只剩之前的结算")
    func todayBecomesDayOff() throws {
        let state = try editing(feb(11), .setOverride(.dayOff), in: try installedFebruary2())
        let snap = snapshot(of: state, at: standardDay(15, 0))

        #expect(snap.today?.status == .restDay)
        #expect(snap.menuBar.text == nil)
        // 2 月 2 日至 10 日 7 个应出勤日，日薪 20000 ÷ 19。
        #expect(snap.today.map { rounded4($0.monthToDate) } == rounded4(Decimal(20000) / 19 * 7))
    }

    @Test("AC-HOME-09 本月全部覆盖为不上班：提示【本月没有要上班的日子】，本月累计 ¥0")
    func wholeMonthOff() throws {
        var state = try installedFebruary2()
        for day in 1...28 where !LocalDate(year: 2026, month: 2, day: day).isSaturdayOrSunday {
            state = try editing(feb(day), .setOverride(.dayOff), in: state)
        }
        let snap = snapshot(of: state, at: standardDay(15, 0))
        let panel = try #require(snap.panel)

        #expect(panel.notices == ["本月没有要上班的日子"])
        guard case .rest(let rest) = panel.body else {
            Issue.record("期望休息日面板")
            return
        }
        #expect(rest.stats.contains(StatItem(title: "本月累计", value: "¥0")))
        #expect(try monthStat(state, february, "应出勤日数") == "0 天")
        #expect(try monthStat(state, february, "结算总额") == "¥0")
    }

    @Test("有应出勤日的月份没有这条提示")
    func noNoticeNormally() throws {
        #expect(snapshot(of: try installedFebruary2(), at: standardDay(15, 0)).panel?.notices == [])
    }

    @Test("单日覆盖可以设在未来，也随状态文件存取")
    func futureAndPersistence() throws {
        let state = try editing(LocalDate(year: 2026, month: 5, day: 9), .setOverride(.workday), in: try installedFebruary2())
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(restored != (try installedFebruary2()))
    }
}

@Suite("历史编辑：补记扣钱与请假")
struct BackfillTests {
    @Test("AC-CAL-03 上周三补记 50 元：该天结算 950，本月累计减少 50")
    func backfillDeduction() throws {
        let before = try installedFebruary2()
        let after = try editing(feb(4), .addDeduction(fifty), in: before)
        let monthToDate = { (state: AppState) in snapshot(of: state, at: standardDay(15, 0)).today.map { rounded4($0.monthToDate) } }

        #expect(try detail(after, feb(4)).stats == [StatItem(title: "结算", value: "¥950")])
        #expect(try detail(after, feb(4)).deductions.map(\.amount) == ["−¥50"])
        #expect(monthToDate(after).map { $0 + 50 } == monthToDate(before))
    }

    @Test("补记的扣钱可以修改和删除")
    func editAndDeletePastDeduction() throws {
        let added = try editing(feb(4), .addDeduction(fifty), in: try installedFebruary2())
        let id = try #require(try detail(added, feb(4)).deductions.first?.id)
        let edited = try editing(feb(4), .editDeduction(id: id, DeductionInput(amount: .fixed(80), reason: nil, note: "")), in: added)
        let deleted = try editing(feb(4), .deleteDeduction(id: id), in: edited)

        #expect(try detail(edited, feb(4)).stats == [StatItem(title: "结算", value: "¥920")])
        #expect(try detail(deleted, feb(4)).stats == [StatItem(title: "结算", value: "¥1000")])
        #expect(deleted == (try installedFebruary2()))
    }

    @Test("别的日子的扣钱不能用这一天的编号去改")
    func deductionOnOtherDay() throws {
        let added = try editing(feb(4), .addDeduction(fifty), in: try installedFebruary2())
        let id = try #require(try detail(added, feb(4)).deductions.first?.id)

        #expect(try rejection(feb(5), .deleteDeduction(id: id), in: added) == .deductionNotFound)
    }

    @Test("AC-FINE-03 今天记日薪 10% 后把一个周六改成上班日：该笔扣款变为 95.2381 元")
    func percentFollowsDailyWage() throws {
        let percent = Command.addDeduction(DeductionInput(amount: .percentOfDailyWage(10), reason: nil, note: ""))
        let fined = try apply(percent, to: try installedFebruary2(), at: standardDay(15, 0)).state
        let state = try editing(feb(7), .setOverride(.workday), in: fined)

        #expect(try attendancePanel(fined, at: standardDay(15, 0)).deductions.map(\.amount) == ["−¥100"])
        #expect(try attendancePanel(state, at: standardDay(15, 0)).deductions.map(\.amount) == ["−¥95.2381"])
    }

    @Test("AC-LEAVE-06 历史日历给下周三请全天假 (默认 100%)：当天预计结算 0，本月应出勤日数不变")
    func futureLeave() throws {
        let leave = Leave(period: .fullDay, deductionPercent: LeavePeriod.fullDay.defaultDeductionPercent)
        let state = try editing(feb(18), .requestLeave(leave), in: try installedFebruary2())
        let day = try #require(snapshot(of: state, at: standardDay(15, 0)).historyDay(feb(18)))

        #expect(day.detail.stats == [StatItem(title: "预计结算", value: "¥0")])
        #expect(day.kind == .leave)
        #expect(try monthStat(state, february, "应出勤日数") == "20 天")
    }

    @Test("过去的请假可以补请、修改 (整条替换) 和撤销，上下午合并规则与今天相同")
    func pastLeave() throws {
        var state = try editing(feb(4), .requestLeave(Leave(period: .morning, deductionPercent: 50)), in: try installedFebruary2())
        state = try editing(feb(4), .requestLeave(Leave(period: .afternoon, deductionPercent: 20)), in: state)
        #expect(try detail(state, feb(4)).leave == HistoryLine(title: "全天假", detail: "扣薪 70%", value: "−¥700"))

        state = try editing(feb(4), .editLeave(Leave(period: .afternoon, deductionPercent: 0)), in: state)
        #expect(try detail(state, feb(4)).stats == [StatItem(title: "结算", value: "¥1000")])

        state = try editing(feb(4), .cancelLeave, in: state)
        #expect(state == (try installedFebruary2()))
    }

    @Test("AC-CAL-04 下周三只能请假和设置单日覆盖：记扣钱、补记白干被拒绝")
    func futureDayLimits() throws {
        let state = try installedFebruary2()
        let segment = UnpaidWorkInput(start: TimeOfDay(hour: 18, minute: 0), end: TimeOfDay(hour: 19, minute: 0))

        #expect(try rejection(feb(18), .addDeduction(fifty), in: state) == .futureDate)
        #expect(try rejection(feb(18), .addUnpaidWork(segment), in: state) == .futureDate)
        #expect(CommandError.futureDate.message == "还没到这一天，只能请假或设置单日覆盖")
        #expect(throws: Never.self) { try editing(feb(18), .requestLeave(Leave(period: .fullDay, deductionPercent: 100)), in: state) }
        #expect(throws: Never.self) { try editing(feb(18), .setOverride(.dayOff), in: state) }
    }

    @Test("#8 给不应出勤的日子记扣钱或请假：被拒绝，提示【今天本来就不上班】")
    func notAttendanceDay() throws {
        let state = try editing(feb(4), .setOverride(.dayOff), in: try installedFebruary2())

        #expect(try rejection(feb(7), .addDeduction(fifty), in: state) == .notAttendanceDay)
        #expect(try rejection(feb(4), .addDeduction(fifty), in: state) == .notAttendanceDay)
        #expect(try rejection(feb(4), .requestLeave(Leave(period: .fullDay, deductionPercent: 100)), in: state) == .notAttendanceDay)
        #expect(CommandError.notAttendanceDay.message == "今天本来就不上班")
    }

    @Test("安装当月之前的日子没有历史，不能编辑")
    func beforeInstallMonth() throws {
        let state = try installedFebruary2()

        #expect(try rejection(LocalDate(year: 2026, month: 1, day: 30), .addDeduction(fifty), in: state) == .dateOutOfRange)
        #expect(try rejection(LocalDate(year: 2026, month: 1, day: 30), .setOverride(.workday), in: state) == .dateOutOfRange)
        // 安装当月、安装日之前的日子可以补记。
        #expect(throws: Never.self) { try editing(feb(1), .setOverride(.workday), in: state) }
    }
}

@Suite("历史编辑：变成不上班日的那天")
struct StaleRecordTests {
    @Test("#14 遗留 单日覆盖后某天不上班：已有的扣钱和请假仍在详情里，提示不计入，可以删除")
    func overrideHidesNothing() throws {
        var state = try editing(feb(4), .addDeduction(fifty), in: try installedFebruary2())
        state = try editing(feb(4), .requestLeave(Leave(period: .afternoon, deductionPercent: 50)), in: state)
        state = try editing(feb(4), .setOverride(.dayOff), in: state)
        let off = try detail(state, feb(4))
        let id = try #require(off.deductions.first?.id)

        #expect(off.stats.isEmpty)
        #expect(off.deductions.map(\.amount) == ["−¥50"])
        #expect(off.leave?.title == "下午假")
        #expect(off.notice == "这天不上班，下面的扣钱和请假不计入结算，可以删掉")

        state = try editing(feb(4), .deleteDeduction(id: id), in: state)
        state = try editing(feb(4), .cancelLeave, in: state)
        let cleaned = try detail(state, feb(4))
        #expect(cleaned.deductions.isEmpty)
        #expect(cleaned.leave == nil)
        #expect(cleaned.notice == nil)
    }

    @Test("#14 遗留 节假日表更新后某天成了法定节假日：那天的扣钱仍可见、可删除")
    func holidayUpdateHidesNothing() throws {
        let state = try editing(feb(4), .addDeduction(fifty), in: try installedFebruary2())
        let holidays = HolidayTable(days: [feb(4): .holiday])
        let off = try detail(state, feb(4), holidays: holidays)
        let id = try #require(off.deductions.first?.id)

        #expect(off.deductions.map(\.amount) == ["−¥50"])
        #expect(off.notice != nil)
        #expect(throws: Never.self) { try editing(feb(4), .deleteDeduction(id: id), in: state, holidays: holidays) }
    }

    @Test("不上班的那天已有的扣钱不能修改，只能删除")
    func staleDeductionNotEditable() throws {
        var state = try editing(feb(4), .addDeduction(fifty), in: try installedFebruary2())
        state = try editing(feb(4), .setOverride(.dayOff), in: state)
        let id = try #require(try detail(state, feb(4)).deductions.first?.id)

        #expect(try rejection(feb(4), .editDeduction(id: id, fifty), in: state) == .notAttendanceDay)
    }
}

@Suite("历史编辑：月薪")
struct HistorySalaryTests {
    /// 1 月 5 日安装，月薪 20000；2026 年 1 月按双休 22 个应出勤日。
    private func installedJanuary() throws -> AppState {
        try onboarded(at: moment(2026, 1, 5, 9, 0))
    }

    @Test("AC-CAL-05 把上个月月薪从 20000 改为 22000：上个月重算，本月不变")
    func changeLastMonth() throws {
        let january = YearMonth(year: 2026, month: 1)
        let state = try apply(.setMonthlySalary(january, 22000), to: try installedJanuary(), at: standardDay(15, 0)).state
        let snap = snapshot(of: state, at: standardDay(15, 0))

        #expect(try monthStat(state, january, "结算总额") == "¥22000")
        #expect(try monthStat(try installedJanuary(), january, "结算总额") == "¥20000")
        #expect(snap.today?.dailyWage == 1000)
        #expect(try #require(snap.historyMonth(january)).salary == StatItem(title: "月薪", value: "¥22000"))
        #expect(try #require(snap.historyMonth(february)).salary == StatItem(title: "月薪", value: "¥20000"))
        // 3 月起沿用最近一次设置的月薪 (本月的 20000)。
        #expect(snapshot(of: state, at: moment(2026, 3, 10, 15, 0)).today?.dailyWage == Decimal(20000) / 22)
    }

    @Test("在历史里改本月月薪与设置页一样，未来月份沿用")
    func changeCurrentMonth() throws {
        let viaHistory = try apply(.setMonthlySalary(february, 30000), to: try installedJanuary(), at: standardDay(15, 0)).state
        let viaSettings = try apply(.changeMonthlySalary(30000), to: try installedJanuary(), at: standardDay(15, 0)).state

        #expect(viaHistory == viaSettings)
        #expect(snapshot(of: viaHistory, at: moment(2026, 3, 10, 15, 0)).today?.dailyWage == Decimal(30000) / 22)
    }

    @Test("月薪校验与设置页相同；安装当月之前、本月之后的月份不能改")
    func validation() throws {
        let state = try installedJanuary()
        let now = standardDay(15, 0)

        #expect(throws: CommandError.salaryNotPositive) { try apply(.setMonthlySalary(february, 0), to: state, at: now) }
        #expect(throws: CommandError.dateOutOfRange) { try apply(.setMonthlySalary(YearMonth(year: 2025, month: 12), 1), to: state, at: now) }
        #expect(throws: CommandError.dateOutOfRange) { try apply(.setMonthlySalary(YearMonth(year: 2026, month: 3), 1), to: state, at: now) }
    }
}

@Suite("历史编辑：目标")
struct HistoryEditGoalTests {
    @Test("AC-GOAL-08 目标完成后补记完成前某天扣钱：已完成目标不变，当前目标累计额减少")
    func completedGoalFrozen() throws {
        var state = try creatingGoal("键盘", 1000, in: try installedFebruary2(), at: moment(2026, 2, 2, 9, 0))
        state = try apply(.advance, to: state, at: moment(2026, 2, 3, 9, 0)).state
        state = try creatingGoal("Switch 2", 5000, in: state, at: moment(2026, 2, 3, 9, 0))
        let now = moment(2026, 2, 5, 9, 0)
        let before = try #require(snapshot(of: state, at: now).goals)

        state = try editing(feb(2), .addDeduction(fifty), in: state, at: now)
        let after = try #require(snapshot(of: state, at: now).goals)

        #expect(before.map(\.detail) == ["¥2000 / ¥5000", "¥1000 · 2月3日达成"])
        #expect(after.map(\.detail) == ["¥1950 / ¥5000", "¥1000 · 2月3日达成"])
        #expect(after.map(\.statusLabel) == ["累计中", "已完成"])
    }

    @Test("本月没有要上班的日子时，目标预计完成不按日薪 0 去除")
    func estimateWithoutAttendanceDays() throws {
        var state = try creatingGoal("键盘", 1000, in: try installedFebruary2(), at: moment(2026, 2, 2, 9, 0))
        for day in 1...28 where !LocalDate(year: 2026, month: 2, day: day).isSaturdayOrSunday {
            state = try editing(feb(day), .setOverride(.dayOff), in: state)
        }

        #expect(try activeGoal(state, at: standardDay(15, 0)).estimate == "本月没有要上班的日子，暂时没法预计")
    }
}

@Suite("历史编辑：白干段")
struct UnpaidWorkEditTests {
    private func segment(_ startHour: Int, _ startMinute: Int, _ endHour: Int, _ endMinute: Int) -> UnpaidWorkInput {
        UnpaidWorkInput(start: TimeOfDay(hour: startHour, minute: startMinute), end: TimeOfDay(hour: endHour, minute: endMinute))
    }

    @Test("PRD 4.4.3 #5 补记 2 月 9 日 18:00 至 19:30：白干 1:30 · 倒贴 ¥214.2857，结算不变")
    func backfill() throws {
        let state = try editing(feb(9), .addUnpaidWork(segment(18, 0, 19, 30)), in: try installedFebruary2())
        let day = try detail(state, feb(9))

        #expect(day.unpaidWork == [HistoryLine(title: "18:00 至 19:30", detail: nil, value: "1:30")])
        #expect(day.unpaidWorkSummary == "白干 1:30 · 倒贴 ¥214.2857")
        #expect(day.stats == [StatItem(title: "结算", value: "¥1000")])
    }

    @Test("休息日也能补记 (被迫营业)，多段按开始时刻排列，可修改、删除")
    func editAndDelete() throws {
        var state = try editing(feb(7), .addUnpaidWork(segment(14, 0, 15, 0)), in: try installedFebruary2())
        state = try editing(feb(7), .addUnpaidWork(segment(9, 0, 10, 0)), in: state)
        #expect(try detail(state, feb(7)).unpaidWork.map(\.title) == ["09:00 至 10:00", "14:00 至 15:00"])

        state = try editing(feb(7), .editUnpaidWork(index: 1, segment(14, 0, 16, 30)), in: state)
        #expect(try detail(state, feb(7)).unpaidWorkSummary?.hasPrefix("白干 3:30") == true)

        state = try editing(feb(7), .deleteUnpaidWork(index: 0), in: state)
        state = try editing(feb(7), .deleteUnpaidWork(index: 0), in: state)
        #expect(state == (try installedFebruary2()))
    }

    @Test("修改被自动停止的那段：去掉疑似通宵标记")
    func editClearsAllNighter() throws {
        var state = try apply(.startUnpaidWork, to: try installedFebruary2(), at: moment(2026, 2, 9, 18, 0)).state
        state = try apply(.advance, to: state, at: moment(2026, 2, 10, 9, 0)).state
        state = try editing(feb(9), .editUnpaidWork(index: 0, segment(18, 0, 22, 0)), in: state)

        #expect(try detail(state, feb(9)).unpaidWork == [HistoryLine(title: "18:00 至 22:00", detail: nil, value: "4:00")])
    }

    @Test("白干段校验：结束要晚于开始，不能和已有的段重叠，今天的不能晚于此刻，编号要存在")
    func validation() throws {
        let state = try editing(feb(9), .addUnpaidWork(segment(18, 0, 19, 30)), in: try installedFebruary2())

        #expect(try rejection(feb(9), .addUnpaidWork(segment(20, 0, 20, 0)), in: state) == .unpaidWorkEndNotAfterStart)
        #expect(try rejection(feb(9), .addUnpaidWork(segment(19, 0, 20, 0)), in: state) == .unpaidWorkOverlap)
        #expect(try rejection(feb(11), .addUnpaidWork(segment(14, 0, 16, 0)), in: state) == .unpaidWorkInFuture)
        #expect(try rejection(feb(9), .deleteUnpaidWork(index: 3), in: state) == .unpaidWorkNotFound)
        #expect(try rejection(feb(9), .editUnpaidWork(index: 1, segment(20, 0, 21, 0)), in: state) == .unpaidWorkNotFound)
        // 改自己那段不算重叠。
        #expect(throws: Never.self) { try editing(feb(9), .editUnpaidWork(index: 0, segment(18, 30, 19, 45)), in: state) }
        #expect(CommandError.unpaidWorkEndNotAfterStart.message == "结束时间要晚于开始时间")
        #expect(CommandError.unpaidWorkOverlap.message == "和这天已有的白干段重叠了")
        #expect(CommandError.unpaidWorkInFuture.message == "还没到这个时间")
    }

    @Test("计时中的那段不能改，只能删；补记不能和它重叠")
    func runningSegment() throws {
        let running = try apply(.startUnpaidWork, to: try installedFebruary2(), at: standardDay(18, 0)).state
        let now = standardDay(19, 0)

        #expect(try rejection(feb(11), .editUnpaidWork(index: 0, segment(18, 0, 18, 30)), in: running, at: now) == .unpaidWorkAlreadyRunning)
        #expect(try rejection(feb(11), .addUnpaidWork(segment(18, 10, 18, 20)), in: running, at: now) == .unpaidWorkOverlap)
        #expect(try editing(feb(11), .deleteUnpaidWork(index: 0), in: running, at: now) == (try installedFebruary2()))
    }
}

/// 2026 年国庆：10 月 1 日至 7 日放假，10 月 10 日周六调休上班。
private let nationalDay2026 = HolidayTable(
    days: Dictionary(uniqueKeysWithValues: (1...7).map { (LocalDate(year: 2026, month: 10, day: $0), HolidayKind.holiday) }
        + [(LocalDate(year: 2026, month: 10, day: 10), HolidayKind.makeupDay)])
)

extension LocalDate {
    /// 测试侧判断周六日：2026 年 2 月 1 日是周日。
    var isSaturdayOrSunday: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return calendar.isDateInWeekend(date)
    }
}
