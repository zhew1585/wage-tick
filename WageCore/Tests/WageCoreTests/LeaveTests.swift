import Foundation
import Testing
import WageCore

// 请假 (PRD 4.4.2、F6)：今天请全天、上午或下午假。未来日期请假留给历史编辑票。
// 未特别说明时都在标准算例的 2026-02-11 (周三，2 月第 8 个应出勤日) 09:00 请假。

/// 在 `at` 时刻对 `state` 执行一条请假相关命令。
func sending(_ command: Command, to state: AppState, at now: Moment = standardDay(9, 0)) throws -> AppState {
    try apply(command, to: state, at: now).state
}

/// 标准算例下今天 09:00 请一条假后的状态。
func onLeave(_ period: LeavePeriod, _ percent: Decimal, schedule: WorkSchedule = standardSchedule) throws -> AppState {
    try sending(.requestLeave(Leave(period: period, deductionPercent: percent)), to: try onboarded(schedule: schedule))
}

@Suite("请假：半天假")
struct HalfDayLeaveTests {
    @Test("AC-LEAVE-01 今天请下午假 (默认 50%)，11:00 打开：今日上限 500，今日已赚 250.0000，倒计时到 12:00")
    func afternoonLeaveAt1100() throws {
        let state = try onLeave(.afternoon, LeavePeriod.afternoon.defaultDeductionPercent)
        let snap = snapshot(of: state, at: standardDay(11, 0))
        let body = try attendancePanel(state, at: standardDay(11, 0))

        #expect(snap.today?.status == .working)
        #expect(snap.today?.earnings?.cap == 500)
        #expect(snap.menuBar == MenuBarDisplay(pose: .grinding, text: "250.0000"))
        #expect(body.headline == "¥250.0000")
        #expect(body.progress?.label == "已工作 1 / 2 小时")
        #expect(body.progress?.percent == "50%")
        #expect(body.stats.first == StatItem(title: "距离下班", value: "1:00:00"))
        #expect(body.caption.hasPrefix("今日上限 ¥500 · "))
    }

    @Test("AC-LEAVE-02 下午假 12:00 之后：状态【已下班】，结算 500", arguments: [(12, 0), (12, 30), (18, 30)])
    func afternoonLeaveOffWork(time: (Int, Int)) throws {
        let state = try onLeave(.afternoon, 50)
        let panel = try #require(snapshot(of: state, at: standardDay(time.0, time.1)).panel)
        let body = try attendancePanel(state, at: standardDay(time.0, time.1))

        #expect(panel.statusLabel == "已下班")
        #expect(body.headline == "¥500.0000")
        // 2 月 11 日前 7 个应出勤日满勤 7000，加今日结算 500；请假扣薪计入当日扣款。
        #expect(body.stats == [
            StatItem(title: "今日结算", value: "¥500"),
            StatItem(title: "扣款", value: "−¥500"),
            StatItem(title: "本月累计", value: "¥7500"),
        ])
    }

    @Test("AC-LEAVE-03 今天请上午假，11:00：状态【未上班】、菜单栏 0.0000；午休时段不经过午休中；13:00 起上班中")
    func morningLeave() throws {
        let state = try onLeave(.morning, 50)

        #expect(snapshot(of: state, at: standardDay(11, 0)).today?.status == .notStarted)
        #expect(snapshot(of: state, at: standardDay(11, 0)).menuBar == MenuBarDisplay(pose: .yawning, text: "0.0000"))
        #expect(snapshot(of: state, at: standardDay(12, 30)).today?.status == .notStarted)
        #expect(snapshot(of: state, at: standardDay(13, 0)).today?.status == .working)
        // 当日计划 13:00 至 18:00，15:00 时走了 2 / 5，今日已赚 = 500 × 0.4。
        #expect(snapshot(of: state, at: standardDay(15, 0)).menuBar.text == "200.0000")
        #expect(try attendancePanel(state, at: standardDay(15, 0)).stats.first == StatItem(title: "距离下班", value: "3:00:00"))
    }

    @Test("PRD 4.3.5 #20 关闭午休时半天假以计划上下班中点为分界")
    func halfDayWithoutLunchSplitsAtMidpoint() throws {
        // 10:00 至 18:00 无午休，中点 14:00。
        let noLunch = WorkSchedule(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0), lunch: nil)
        let afternoon = try onLeave(.afternoon, 50, schedule: noLunch)
        let morning = try onLeave(.morning, 50, schedule: noLunch)

        // 下午假：当日计划 10:00 至 14:00，13:00 时走了 3 / 4。
        #expect(snapshot(of: afternoon, at: standardDay(13, 0)).menuBar.text == "375.0000")
        #expect(snapshot(of: afternoon, at: standardDay(14, 0)).today?.status == .offWork)
        // 上午假：当日计划 14:00 至 18:00。
        #expect(snapshot(of: morning, at: standardDay(13, 59)).today?.status == .notStarted)
        #expect(snapshot(of: morning, at: standardDay(16, 0)).menuBar.text == "250.0000")
    }

    @Test("PRD 4.3.5 #20 中点不落在整分上 (09:00 至 18:01)：按精确中点切分")
    func midpointWithSeconds() throws {
        let noLunch = WorkSchedule(start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 18, minute: 1), lunch: nil)
        let state = try onLeave(.afternoon, 50, schedule: noLunch)

        #expect(snapshot(of: state, at: standardDay(13, 30, 29)).today?.status == .working)
        #expect(snapshot(of: state, at: standardDay(13, 30, 30)).today?.status == .offWork)
    }

    @Test("PRD 4.3.5 #3 午休紧贴计划上班时请下午假：当日计划没有有效工时，到点即已下班、收入为今日上限，不崩溃")
    func halfDayWithNoWorkingHours() throws {
        let schedule = WorkSchedule(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0),
            lunch: LunchBreak(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 11, minute: 0))
        )
        let state = try onLeave(.afternoon, 50, schedule: schedule)
        let before = try attendancePanel(state, at: standardDay(9, 30))

        #expect(snapshot(of: state, at: standardDay(9, 30)).menuBar.text == "0.0000")
        #expect(before.progress?.percent == "0%")
        #expect(before.progress?.segments == [])
        #expect(snapshot(of: state, at: standardDay(10, 0)).today?.status == .offWork)
        #expect(snapshot(of: state, at: standardDay(10, 0)).menuBar.text == "500.0000")
    }
}

@Suite("请假：全天假")
struct FullDayLeaveTests {
    @Test("AC-HOME-07 今天全天请假：面板显示【今天请假】，菜单栏同休息日")
    func fullDayLeavePresentsAsRestDay() throws {
        let state = try onLeave(.fullDay, 100)
        let snap = snapshot(of: state, at: standardDay(11, 0))
        let panel = try #require(snap.panel)

        #expect(snap.today?.status == .restDay)
        #expect(snap.today?.isEarning == false)
        #expect(snap.menuBar == MenuBarDisplay(pose: .sunbathing, text: nil))
        #expect(panel.statusLabel == "休息日")
        #expect(panel.body == .rest(RestPanel(
            headline: "今天请假",
            stats: [
                StatItem(title: "本月已上班", value: "7 天"),
                // 默认扣 100%，今日结算 0。
                StatItem(title: "本月累计", value: "¥7000"),
                StatItem(title: "下一个应出勤日", value: "2月12日 周四"),
            ]
        )))
    }

    @Test("AC-LEAVE-04 全天请假扣薪比例改为 0%：状态按休息日呈现，结算 1000")
    func fullDayLeaveWithoutDeduction() throws {
        let state = try onLeave(.fullDay, 0)
        let today = try #require(snapshot(of: state, at: standardDay(9, 30)).today)

        #expect(today.status == .restDay)
        #expect(today.earnings?.cap == 1000)
        // 全天请假不滚动，今日已赚直接为今日上限，计入本月累计。
        #expect(today.monthToDate == 8000)
        // 次日本月累计里，这一天按结算 1000 计入。
        #expect(snapshot(of: state, at: moment(2026, 2, 12, 9, 0)).today?.monthToDate == 8000)
    }

    @Test("PRD 4.3.5 #18 上班中途改为全天请假：状态立即变为休息日")
    func switchToFullDayMidShift() throws {
        let state = try onboarded()
        #expect(snapshot(of: state, at: standardDay(15, 0)).today?.status == .working)

        let onLeave = try sending(.requestLeave(Leave(period: .fullDay, deductionPercent: 100)), to: state, at: standardDay(15, 0))

        #expect(snapshot(of: onLeave, at: standardDay(15, 0)).today?.status == .restDay)
        #expect(snapshot(of: onLeave, at: standardDay(15, 0)).menuBar == MenuBarDisplay(pose: .sunbathing, text: nil))
    }

    @Test("PRD 4.2.2 请假日仍计入应出勤日数：日薪不变")
    func leaveDayStillCountsAsAttendanceDay() throws {
        let state = try onLeave(.fullDay, 100)

        #expect(snapshot(of: state, at: standardDay(11, 0)).today?.dailyWage == 1000)
        // 次日的日薪和已上班天数仍按 20 个应出勤日算，请假那天计入已上班。
        let tomorrow = try #require(snapshot(of: state, at: moment(2026, 2, 12, 11, 0)).today)
        #expect(tomorrow.dailyWage == 1000)
        #expect(tomorrow.attendedDays == 8)
    }
}

@Suite("请假：本月累计逐日结算")
struct LeaveMonthToDateTests {
    @Test("PRD 4.3.4 本月累计 = 今天之前各应出勤日的结算之和：昨天下午假 50%，今天 15:00 = 7 × 1000 + 500 + 571.4286")
    func monthToDateSumsDailySettlements() throws {
        let state = try onLeave(.afternoon, 50)
        let body = try attendancePanel(state, at: moment(2026, 2, 12, 15, 0))

        #expect(body.stats.last == StatItem(title: "本月累计", value: "¥8071.4286"))
    }

    @Test("PRD 4.4.2 #1 请假扣薪按当月日薪：5 月日薪 20000 ÷ 21，下午假 50%，今日上限 476.1905")
    func leaveDeductionFollowsDailyWage() throws {
        let state = try sending(
            .requestLeave(Leave(period: .afternoon, deductionPercent: 50)),
            to: try onboarded(),
            at: moment(2026, 5, 6, 9, 0)
        )

        #expect(rounded4(try #require(snapshot(of: state, at: moment(2026, 5, 6, 18, 0)).today?.earnings).cap) == rounded4(Decimal(10000) / Decimal(21)))
        #expect(snapshot(of: state, at: moment(2026, 5, 6, 18, 0)).menuBar.text == "476.1905")
    }
}

@Suite("请假：与扣钱记录合计")
struct LeaveWithDeductionTests {
    private let fifty = Command.addDeduction(DeductionInput(amount: .fixed(50), reason: .late, note: ""))

    @Test("GLOSSARY 当日扣款 = 扣钱记录合计 + 请假扣薪：下午假 50% 再扣 50，今日上限 450，已下班统计行扣款 −¥550")
    func deductionAndLeaveAddUp() throws {
        let state = try sending(fifty, to: try onLeave(.afternoon, 50))
        let body = try attendancePanel(state, at: standardDay(12, 30))

        #expect(snapshot(of: state, at: standardDay(11, 0)).today?.earnings?.cap == 450)
        #expect(snapshot(of: state, at: standardDay(11, 0)).today?.earnings?.deductionTotal == 550)
        #expect(body.stats == [
            StatItem(title: "今日结算", value: "¥450"),
            StatItem(title: "扣款", value: "−¥550"),
            StatItem(title: "本月累计", value: "¥7450"),
        ])
        // 次日本月累计里，这一天按结算 450 计入。
        #expect(snapshot(of: state, at: moment(2026, 2, 12, 9, 0)).today?.monthToDate == 7450)
    }

    @Test("PRD 4.3.4【D1】全天请假 100% 再扣钱：今日上限停在 0，提示今天已经白干了")
    func fullDayLeavePlusDeductionFloorsAtZero() throws {
        let state = try sending(fifty, to: try onLeave(.fullDay, 100))
        let snap = snapshot(of: state, at: standardDay(11, 0))

        #expect(snap.today?.earnings?.cap == 0)
        #expect(snap.today?.monthToDate == 7000)
        #expect(snap.panel?.deductionEntry?.warning == "今天已经白干了，再扣就倒贴了")
    }

    @Test("撤销请假后扣钱记录保留；删掉最后一笔扣钱后请假保留")
    func leaveAndDeductionsShareOneDayRecord() throws {
        let both = try sending(fifty, to: try onLeave(.afternoon, 50))
        let leaveCancelled = try sending(.cancelLeave, to: both)
        let id = try #require(snapshot(of: both, at: standardDay(11, 0)).panel.flatMap {
            if case .attendance(let body) = $0.body { body.deductions.first?.id } else { nil }
        })
        let deductionDeleted = try sending(.deleteDeduction(id: id), to: both)

        #expect(snapshot(of: leaveCancelled, at: standardDay(11, 0)).today?.earnings?.cap == 950)
        #expect(snapshot(of: deductionDeleted, at: standardDay(11, 0)).today?.earnings?.cap == 500)
        #expect(try sending(.cancelLeave, to: deductionDeleted) == (try onboarded()))
    }
}

@Suite("请假：合并、编辑与撤销")
struct LeaveEditingTests {
    @Test("AC-LEAVE-05 先请上午假 (50%) 再请下午假 (20%)：合并为全天假，扣薪比例 70%")
    func morningThenAfternoonMerges() throws {
        let morning = try onLeave(.morning, 50)
        let merged = try sending(.requestLeave(Leave(period: .afternoon, deductionPercent: 20)), to: morning)
        let today = try #require(snapshot(of: merged, at: standardDay(11, 0)).today)

        #expect(today.leave == Leave(period: .fullDay, deductionPercent: 70))
        #expect(today.status == .restDay)
        #expect(today.earnings?.cap == 300)
    }

    @Test("PRD 4.3.5 #21 合并后的扣薪比例最高 100%")
    func mergedPercentCapsAt100() throws {
        let afternoon = try onLeave(.afternoon, 60)
        let merged = try sending(.requestLeave(Leave(period: .morning, deductionPercent: 70)), to: afternoon)

        #expect(snapshot(of: merged, at: standardDay(11, 0)).today?.leave == Leave(period: .fullDay, deductionPercent: 100))
        #expect(snapshot(of: merged, at: standardDay(11, 0)).today?.earnings?.cap == 0)
    }

    @Test("PRD 4.4.2 #4 同一天只有一条请假：再请同一个半天或全天时，新的一条替换旧的")
    func sameHalfOrFullDayReplaces() throws {
        let again = try sending(.requestLeave(Leave(period: .morning, deductionPercent: 30)), to: try onLeave(.morning, 50))
        let fullThenHalf = try sending(.requestLeave(Leave(period: .afternoon, deductionPercent: 50)), to: try onLeave(.fullDay, 100))

        #expect(snapshot(of: again, at: standardDay(11, 0)).today?.leave == Leave(period: .morning, deductionPercent: 30))
        #expect(snapshot(of: fullThenHalf, at: standardDay(11, 0)).today?.leave == Leave(period: .afternoon, deductionPercent: 50))
    }

    @Test("PRD 4.4.2 #5 编辑请假：整条替换，上午假改成下午假不会合并")
    func editReplacesWithoutMerging() throws {
        let edited = try sending(.editLeave(Leave(period: .afternoon, deductionPercent: 30)), to: try onLeave(.morning, 50))
        let today = try #require(snapshot(of: edited, at: standardDay(11, 0)).today)

        #expect(today.leave == Leave(period: .afternoon, deductionPercent: 30))
        #expect(today.earnings?.cap == 700)
    }

    @Test("PRD 4.4.2 #5 撤销请假：当天恢复为普通应出勤日")
    func cancelRestoresNormalDay() throws {
        let cancelled = try sending(.cancelLeave, to: try onLeave(.fullDay, 100), at: standardDay(15, 0))
        let snap = snapshot(of: cancelled, at: standardDay(15, 0))

        #expect(snap.today?.leave == nil)
        #expect(snap.today?.status == .working)
        #expect(snap.menuBar.text == "571.4286")
    }

    @Test("撤销时今天没有请假：什么都不变")
    func cancelWithoutLeaveIsNoOp() throws {
        let state = try onboarded()

        #expect(try sending(.cancelLeave, to: state) == state)
    }
}

@Suite("请假：表单")
struct LeaveFormTests {
    @Test("AC-LEAVE-07 时段在全天和半天之间切换：扣薪比例分别带出 100%、50%")
    func defaultPercents() {
        #expect(LeavePeriod.fullDay.defaultDeductionPercent == 100)
        #expect(LeavePeriod.morning.defaultDeductionPercent == 50)
        #expect(LeavePeriod.afternoon.defaultDeductionPercent == 50)
        #expect(LeavePeriod.allCases.map(\.label) == ["全天", "上午", "下午"])
    }

    @Test("AC-LEAVE-08 扣薪比例填 120%：提示【扣薪比例要在 0% 到 100% 之间】", arguments: [Decimal(120), Decimal(-1), Decimal(string: "100.01")!])
    func percentOutOfRangeIsRejected(percent: Decimal) throws {
        let state = try onboarded()

        #expect(throws: CommandError.leavePercentOutOfRange) {
            try apply(.requestLeave(Leave(period: .afternoon, deductionPercent: percent)), to: state, at: standardDay(9, 0))
        }
        #expect(throws: CommandError.leavePercentOutOfRange) {
            try apply(.editLeave(Leave(period: .afternoon, deductionPercent: percent)), to: state, at: standardDay(9, 0))
        }
        #expect(CommandError.leavePercentOutOfRange.message == "扣薪比例要在 0% 到 100% 之间")
    }

    @Test("PRD 4.3.5 #22 扣薪比例为空也提示同一条；0% 和 100% 可以保存")
    func percentBoundaries() throws {
        #expect(Validation.leaveDeductionPercent(nil) == .leavePercentOutOfRange)
        #expect(Validation.leaveDeductionPercent(0) == nil)
        #expect(Validation.leaveDeductionPercent(100) == nil)
        #expect(throws: Never.self) { try onLeave(.fullDay, 0) }
        #expect(throws: Never.self) { try onLeave(.fullDay, 100) }
    }

    @Test("PRD 4.3.5 #8 休息日不能请假：提示【今天本来就不上班】，表单不可用")
    func restDayCannotRequestLeave() throws {
        let state = try onboarded()
        let saturday = moment(2026, 2, 14, 11, 0)

        #expect(throws: CommandError.notAttendanceDay) {
            try apply(.requestLeave(Leave(period: .fullDay, deductionPercent: 100)), to: state, at: saturday)
        }
        #expect(CommandError.notAttendanceDay.message == "今天本来就不上班")
        #expect(snapshot(of: state, at: saturday).leaveForm == nil)
    }

    @Test("F6 表单汇总当日计划、请假扣薪、今日上限：还没请假时为作息原样")
    func summaryWithoutLeave() throws {
        let form = try #require(snapshot(of: try onboarded(), at: standardDay(9, 0)).leaveForm)

        #expect(form.current == nil)
        #expect(form.currentText == nil)
        #expect(form.canRequest)
        #expect(form.summary == [
            StatItem(title: "当日计划", value: "10:00 至 18:00"),
            StatItem(title: "请假扣薪", value: "¥0"),
            StatItem(title: "今日上限", value: "¥1000"),
        ])
    }

    @Test("F6 请下午假 50% 后：当日计划 10:00 至 12:00，请假扣薪 ¥500，今日上限 ¥500")
    func summaryWithAfternoonLeave() throws {
        let form = try #require(snapshot(of: try onLeave(.afternoon, 50), at: standardDay(9, 0)).leaveForm)

        #expect(form.current == Leave(period: .afternoon, deductionPercent: 50))
        #expect(form.currentText == "已请下午假 · 扣薪 50%")
        // 已请半天假时还能再请另一半 (AC-LEAVE-05)。
        #expect(form.canRequest)
        #expect(form.summary == [
            StatItem(title: "当日计划", value: "10:00 至 12:00"),
            StatItem(title: "请假扣薪", value: "¥500"),
            StatItem(title: "今日上限", value: "¥500"),
        ])
    }

    @Test("F6 全天请假 12.5%：当日计划为全天请假，比例与金额截掉末尾 0")
    func summaryWithFullDayLeave() throws {
        let form = try #require(snapshot(of: try onLeave(.fullDay, Decimal(string: "12.5")!), at: standardDay(11, 0)).leaveForm)

        #expect(form.currentText == "已请全天假 · 扣薪 12.5%")
        // 已请全天假时只能修改或撤销。
        #expect(!form.canRequest)
        #expect(form.summary == [
            StatItem(title: "当日计划", value: "全天请假"),
            StatItem(title: "请假扣薪", value: "¥125"),
            StatItem(title: "今日上限", value: "¥875"),
        ])
    }
}

@Suite("请假：读回状态")
struct LeavePersistenceTests {
    @Test("PRD 4.3.5 #14 请假存成 JSON 再读回，快照不变")
    func leaveSurvivesPersistence() throws {
        let state = try onLeave(.afternoon, Decimal(string: "33.3")!)
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(snapshot(of: restored, at: standardDay(11, 0)) == snapshot(of: state, at: standardDay(11, 0)))
    }

    @Test("文件里的扣薪比例超出 0% 至 100% 时拒绝读入")
    func invalidPercentIsRejected() throws {
        let json = String(decoding: try JSONEncoder().encode(try onLeave(.afternoon, 50)), as: UTF8.self)
        let corrupted = json.replacingOccurrences(of: "\"deductionPercent\":\"50\"", with: "\"deductionPercent\":\"120\"")
        #expect(corrupted != json)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AppState.self, from: Data(corrupted.utf8)) }
    }
}
