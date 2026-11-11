import Foundation
import Testing
import WageCore

// 请假 (PRD 4.4.2、F6)：今天请一段时间的假 (全天、前半天、后半天或中间任意一段)。
// 未特别说明时都在标准算例的 2026-02-11 (周三，2 月第 8 个应出勤日) 09:00 请假，
// 作息 10:00 至 18:00、饭点 12:00 至 13:00 (标准工时 7 小时，日薪 1000)。

/// 在 `at` 时刻对 `state` 执行一条请假相关命令。
func sending(_ command: Command, to state: AppState, at now: Moment = standardDay(9, 0)) throws -> AppState {
    try apply(command, to: state, at: now).state
}

/// 「14:00」这样的时刻。
func clock(_ text: String) -> TimeOfDay {
    let parts = text.split(separator: ":").map { Int($0)! }
    return TimeOfDay(hour: parts[0], minute: parts[1])
}

/// 一段时间的请假，如 `leave("14:00", "16:00", 50)`。
func leave(_ start: String, _ end: String, _ percent: Decimal) -> Leave {
    Leave(start: clock(start), end: clock(end), deductionPercent: percent)
}

/// 标准算例的全天、前半天、后半天。
func fullDayLeave(_ percent: Decimal) -> Leave { leave("10:00", "18:00", percent) }
func firstHalfLeave(_ percent: Decimal) -> Leave { leave("10:00", "12:00", percent) }
func secondHalfLeave(_ percent: Decimal) -> Leave { leave("13:00", "18:00", percent) }

/// 标准算例下今天 09:00 请一条假后的状态。
func onLeave(_ leave: Leave, schedule: WorkSchedule = standardSchedule) throws -> AppState {
    try sending(.setLeave(leave), to: try onboarded(schedule: schedule))
}

@Suite("请假：前半天、后半天")
struct HalfDayLeaveTests {
    @Test("AC-LEAVE-01 今天请后半天 (50%)，11:00 打开：今日上限 500，今日已赚 250.0000，倒计时到 12:00")
    func secondHalfAt1100() throws {
        let state = try onLeave(secondHalfLeave(50))
        let snap = snapshot(of: state, at: standardDay(11, 0))
        let body = try attendancePanel(state, at: standardDay(11, 0))

        #expect(snap.today?.status == .working)
        #expect(snap.today?.earnings?.cap == 500)
        #expect(snap.menuBar == MenuBarDisplay(pose: .grinding, text: "250.0000"))
        #expect(body.headline == "¥250.0000")
        #expect(body.progress?.label == "已工作 1 / 2 小时")
        #expect(body.progress?.percent == "50.00%")
        #expect(body.stats.first == StatItem(title: "距离下班", value: "1:00:00"))
        #expect(snap.panel?.deductionEntry?.capText == "¥500")
    }

    @Test("AC-LEAVE-02 后半天 12:00 之后：状态【已下班】，结算 500", arguments: [(12, 0), (12, 30), (18, 30)])
    func secondHalfOffWork(time: (Int, Int)) throws {
        let state = try onLeave(secondHalfLeave(50))
        let panel = try #require(snapshot(of: state, at: standardDay(time.0, time.1)).panel)
        let body = try attendancePanel(state, at: standardDay(time.0, time.1))

        #expect(panel.statusLabel == "已下班")
        #expect(body.headline == "¥500.0000")
        // 2 月 11 日前 7 个应出勤日满勤 7000，加今日结算 500；请假扣薪计入当日扣款，并在小字末尾。
        #expect(body.caption == "准点下班，赢 · 扣款 −¥500")
        #expect(body.stats == [
            StatItem(title: "今日结算", value: "¥500"),
            StatItem(title: "距离周末", value: "3 天", tone: .accent),
            StatItem(title: "本月累计", value: "¥7500"),
        ])
    }

    @Test("AC-LEAVE-03 今天请前半天，11:00：状态【未上班】、菜单栏 0.0000；饭点时段不经过干饭中；13:00 起上班中")
    func firstHalf() throws {
        let state = try onLeave(firstHalfLeave(50))

        #expect(snapshot(of: state, at: standardDay(11, 0)).today?.status == .notStarted)
        #expect(snapshot(of: state, at: standardDay(11, 0)).menuBar == MenuBarDisplay(pose: .yawning, text: "0.0000"))
        #expect(snapshot(of: state, at: standardDay(12, 30)).today?.status == .notStarted)
        #expect(snapshot(of: state, at: standardDay(13, 0)).today?.status == .working)
        // 当日计划 13:00 至 18:00，15:00 时走了 2 / 5，今日已赚 = 500 × 0.4。
        #expect(snapshot(of: state, at: standardDay(15, 0)).menuBar.text == "200.0000")
        #expect(try attendancePanel(state, at: standardDay(15, 0)).stats.first == StatItem(title: "距离下班", value: "3:00:00"))
    }

    @Test("PRD 4.3.5 #20 关闭饭点时前半天、后半天以计划上下班中点为分界")
    func halfDayWithoutLunchSplitsAtMidpoint() throws {
        // 10:00 至 18:00 无饭点，中点 14:00。
        let noLunch = WorkSchedule(start: clock("10:00"), end: clock("18:00"), lunch: nil)
        let secondHalf = try onLeave(leave("14:00", "18:00", 50), schedule: noLunch)
        let firstHalf = try onLeave(leave("10:00", "14:00", 50), schedule: noLunch)

        // 后半天：当日计划 10:00 至 14:00，13:00 时走了 3 / 4。
        #expect(snapshot(of: secondHalf, at: standardDay(13, 0)).menuBar.text == "375.0000")
        #expect(snapshot(of: secondHalf, at: standardDay(14, 0)).today?.status == .offWork)
        // 前半天：当日计划 14:00 至 18:00。
        #expect(snapshot(of: firstHalf, at: standardDay(13, 59)).today?.status == .notStarted)
        #expect(snapshot(of: firstHalf, at: standardDay(16, 0)).menuBar.text == "250.0000")
    }

    @Test("PRD 4.3.5 #20 中点不落在整分上 (09:00 至 18:01)：快捷的后半天从 13:30 起")
    func midpointRoundsDownToMinute() throws {
        let noLunch = WorkSchedule(start: clock("09:00"), end: clock("18:01"), lunch: nil)
        let form = try #require(snapshot(of: try onboarded(schedule: noLunch), at: standardDay(9, 0)).leaveForm)
        let secondHalf = try #require(form.bar.quickPicks.last)
        let state = try onLeave(Leave(range: secondHalf.range, deductionPercent: 50), schedule: noLunch)

        #expect(secondHalf.range == LeaveRange(start: clock("13:30"), end: clock("18:01")))
        #expect(snapshot(of: state, at: standardDay(13, 29, 59)).today?.status == .working)
        #expect(snapshot(of: state, at: standardDay(13, 30)).today?.status == .offWork)
    }

    @Test("PRD 4.3.5 #3 饭点紧贴计划上班时请后半天：请掉了全部工时，按全天请假呈现，不崩溃")
    func halfDayWithNoWorkingHoursIsFullDay() throws {
        let schedule = WorkSchedule(
            start: clock("10:00"), end: clock("18:00"), lunch: LunchBreak(start: clock("10:00"), end: clock("11:00"))
        )
        let state = try onLeave(leave("11:00", "18:00", 50), schedule: schedule)
        let snap = snapshot(of: state, at: standardDay(10, 30))

        #expect(snap.today?.status == .restDay)
        #expect(snap.today?.earnings?.cap == 500)
        #expect(snap.leaveForm?.summary.first == StatItem(title: "今天上班", value: "全天请假"))
        // 没有前半天这个快捷时段。
        #expect(snap.leaveForm?.bar.quickPicks.map(\.title) == ["全天", "后半天"])
    }
}

@Suite("请假：中间一段")
struct MiddleLeaveTests {
    /// 14:00 至 16:00 请假，默认比例 2 ÷ 7 = 28.57%，今日上限 714.3。
    private func middle() throws -> AppState {
        try onLeave(leave("14:00", "16:00", Decimal(string: "28.57")!))
    }

    @Test("一天分成两段上班：未上班、上班中、干饭中、上班中、请假中、上班中、已下班", arguments: [
        ((9, 59), DayStatus.notStarted, "未上班"),
        ((11, 0), .working, "上班中"),
        ((12, 30), .lunchBreak, "干饭中"),
        ((13, 30), .working, "上班中"),
        ((14, 0), .onLeave, "请假中"),
        ((15, 59), .onLeave, "请假中"),
        ((16, 0), .working, "上班中"),
        ((18, 0), .offWork, "已下班"),
    ])
    func statusTimeline(time: (Int, Int), status: DayStatus, label: String) throws {
        let snap = snapshot(of: try middle(), at: standardDay(time.0, time.1))

        #expect(snap.today?.status == status)
        #expect(snap.panel?.statusLabel == label)
    }

    @Test("请假中数字停住，小牛晒太阳；16:00 后接着涨，18:00 拿满今日上限")
    func earningsPauseDuringLeave() throws {
        let state = try middle()
        let at1400 = snapshot(of: state, at: standardDay(14, 0))
        let at1530 = snapshot(of: state, at: standardDay(15, 30))

        // 当日有效工时 5 小时 (10-12、13-14、16-18)，14:00 时走了 3 小时：714.3 × 3 ÷ 5。
        #expect(at1400.menuBar == MenuBarDisplay(pose: .sunbathing, text: "428.5800"))
        #expect(at1530.menuBar == at1400.menuBar)
        #expect(at1530.today?.isEarning == false)
        #expect(snapshot(of: state, at: standardDay(17, 0)).menuBar.text == "571.4400")
        #expect(snapshot(of: state, at: standardDay(18, 0)).today?.earnings?.earned == Decimal(string: "714.3"))
    }

    @Test("进度条为三段 (饭点、请假为间隔)，倒计时到 18:00")
    func progressAndCountdown() throws {
        let body = try attendancePanel(try middle(), at: standardDay(15, 0))

        #expect(body.progress?.label == "已工作 3 / 5 小时")
        #expect(body.progress?.segments == [
            ProgressSegment(share: 0.4, filled: 1), ProgressSegment(share: 0.2, filled: 1), ProgressSegment(share: 0.4, filled: 0),
        ])
        #expect(body.progress?.startText == "上班 10:00")
        #expect(body.progress?.endText == "下班 18:00")
        #expect(body.stats.first == StatItem(title: "距离下班", value: "3:00:00"))
    }

    @Test("请假连着结尾 (16:00 至 18:00)：16:00 即已下班")
    func leaveAtEndMovesOffWork() throws {
        let state = try onLeave(leave("16:00", "18:00", 0))

        #expect(snapshot(of: state, at: standardDay(15, 59)).today?.status == .working)
        #expect(snapshot(of: state, at: standardDay(16, 0)).today?.status == .offWork)
        #expect(try attendancePanel(state, at: standardDay(11, 0)).progress?.endText == "下班 16:00")
    }

    @Test("请假从开头跨进饭点 (10:00 至 12:30)：13:00 才上班，中间不经过干饭中")
    func leaveAtStartRunsIntoLunch() throws {
        let state = try onLeave(leave("10:00", "12:30", 0))

        #expect(snapshot(of: state, at: standardDay(12, 40)).today?.status == .notStarted)
        #expect(snapshot(of: state, at: standardDay(13, 0)).today?.status == .working)
        #expect(try attendancePanel(state, at: standardDay(13, 0)).progress?.startText == "上班 13:00")
    }

    @Test("今日上限、扣款与本月累计按扣薪比例：−¥285.70，今日上限 ¥714.30")
    func capFollowsPercent() throws {
        let today = try #require(snapshot(of: try middle(), at: standardDay(11, 0)).today)

        #expect(today.earnings?.cap == Decimal(string: "714.3"))
        #expect(today.earnings?.deductionTotal == Decimal(string: "285.7"))
    }
}

@Suite("请假：全天")
struct FullDayLeaveTests {
    @Test("AC-HOME-07 今天全天请假：面板显示【今天请假】，菜单栏同休息日")
    func fullDayLeavePresentsAsRestDay() throws {
        let state = try onLeave(fullDayLeave(100))
        let snap = snapshot(of: state, at: standardDay(11, 0))
        let panel = try #require(snap.panel)

        #expect(snap.today?.status == .restDay)
        #expect(snap.today?.isEarning == false)
        #expect(snap.menuBar == MenuBarDisplay(pose: .sunbathing, text: nil))
        #expect(panel.statusLabel == "休息日")
        #expect(panel.body == .rest(RestPanel(
            headline: "今天请假",
            tagline: nil,
            nextAttendanceText: "下一个上班日 2月12日 周四",
            stats: [
                StatItem(title: "本月已上班", value: "7/20 天"),
                // 默认扣 100%，今日结算 0。
                StatItem(title: "本月累计", value: "¥7000"),
                StatItem(title: "距离周末", value: "3 天", tone: .accent),
            ]
        )))
    }

    @Test("AC-LEAVE-04 全天请假扣薪比例改为 0%：状态按休息日呈现，结算 1000")
    func fullDayLeaveWithoutDeduction() throws {
        let state = try onLeave(fullDayLeave(0))
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

        let onLeave = try sending(.setLeave(fullDayLeave(100)), to: state, at: standardDay(15, 0))

        #expect(snapshot(of: onLeave, at: standardDay(15, 0)).today?.status == .restDay)
        #expect(snapshot(of: onLeave, at: standardDay(15, 0)).menuBar == MenuBarDisplay(pose: .sunbathing, text: nil))
    }

    @Test("PRD 4.2.2 请假日仍计入应出勤日数：日薪不变")
    func leaveDayStillCountsAsAttendanceDay() throws {
        let state = try onLeave(fullDayLeave(100))

        #expect(snapshot(of: state, at: standardDay(11, 0)).today?.dailyWage == 1000)
        // 次日的日薪和已上班天数仍按 20 个应出勤日算，请假那天计入已上班。
        let tomorrow = try #require(snapshot(of: state, at: moment(2026, 2, 12, 11, 0)).today)
        #expect(tomorrow.dailyWage == 1000)
        #expect(tomorrow.attendedDays == 8)
    }
}

@Suite("请假：本月累计逐日结算")
struct LeaveMonthToDateTests {
    @Test("PRD 4.3.4 本月累计 = 今天之前各应出勤日的结算之和：昨天后半天 50%，今天 15:00 = 7 × 1000 + 500 + 571.4286")
    func monthToDateSumsDailySettlements() throws {
        let state = try onLeave(secondHalfLeave(50))
        let body = try attendancePanel(state, at: moment(2026, 2, 12, 15, 0))

        #expect(body.stats.last == StatItem(title: "本月累计", value: "¥8071.43"))
    }

    @Test("PRD 4.4.2 #1 请假扣薪按当月日薪：5 月日薪 20000 ÷ 21，后半天 50%，今日上限 476.1905")
    func leaveDeductionFollowsDailyWage() throws {
        let state = try sending(.setLeave(secondHalfLeave(50)), to: try onboarded(), at: moment(2026, 5, 6, 9, 0))

        #expect(rounded4(try #require(snapshot(of: state, at: moment(2026, 5, 6, 18, 0)).today?.earnings).cap) == rounded4(Decimal(10000) / Decimal(21)))
        #expect(snapshot(of: state, at: moment(2026, 5, 6, 18, 0)).menuBar.text == "476.1905")
    }
}

@Suite("请假：与扣钱记录合计")
struct LeaveWithDeductionTests {
    private let fifty = Command.addDeduction(DeductionInput(amount: .fixed(50), reason: .late, note: ""))

    @Test("GLOSSARY 当日扣款 = 扣钱记录合计 + 请假扣薪：后半天 50% 再扣 50，今日上限 450，已下班小字末尾扣款 −¥550")
    func deductionAndLeaveAddUp() throws {
        let state = try sending(fifty, to: try onLeave(secondHalfLeave(50)))
        let body = try attendancePanel(state, at: standardDay(12, 30))

        #expect(snapshot(of: state, at: standardDay(11, 0)).today?.earnings?.cap == 450)
        #expect(snapshot(of: state, at: standardDay(11, 0)).today?.earnings?.deductionTotal == 550)
        #expect(body.caption == "准点下班，赢 · 扣款 −¥550")
        #expect(body.stats == [
            StatItem(title: "今日结算", value: "¥450"),
            StatItem(title: "距离周末", value: "3 天", tone: .accent),
            StatItem(title: "本月累计", value: "¥7450"),
        ])
        // 次日本月累计里，这一天按结算 450 计入。
        #expect(snapshot(of: state, at: moment(2026, 2, 12, 9, 0)).today?.monthToDate == 7450)
    }

    @Test("PRD 4.3.4【D1】全天请假 100% 再扣钱：今日上限停在 0，提示今天已经白干了")
    func fullDayLeavePlusDeductionFloorsAtZero() throws {
        let state = try sending(fifty, to: try onLeave(fullDayLeave(100)))
        let snap = snapshot(of: state, at: standardDay(11, 0))

        #expect(snap.today?.earnings?.cap == 0)
        #expect(snap.today?.monthToDate == 7000)
        #expect(snap.panel?.deductionEntry?.warning == "今天已经白干了，再扣就倒贴了")
    }

    @Test("撤销请假后扣钱记录保留；删掉最后一笔扣钱后请假保留")
    func leaveAndDeductionsShareOneDayRecord() throws {
        let both = try sending(fifty, to: try onLeave(secondHalfLeave(50)))
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

@Suite("请假：一天一条、修改与撤销")
struct LeaveEditingTests {
    @Test("PRD 4.4.2 #4 一天只有一条：先请前半天再请后半天，后一条整条替换前一条，不再合并成全天")
    func secondRequestReplaces() throws {
        let replaced = try sending(.setLeave(secondHalfLeave(20)), to: try onLeave(firstHalfLeave(50)))
        let today = try #require(snapshot(of: replaced, at: standardDay(11, 0)).today)

        #expect(today.leave == secondHalfLeave(20))
        #expect(today.status == .working)
        #expect(today.earnings?.cap == 800)
    }

    @Test("PRD 4.4.2 #5 撤销请假：当天恢复为普通应出勤日")
    func cancelRestoresNormalDay() throws {
        let cancelled = try sending(.cancelLeave, to: try onLeave(fullDayLeave(100)), at: standardDay(15, 0))
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

    @Test("请假后改了作息、请假落到计划之外：计划不变，扣薪照扣")
    func leaveOutsideChangedSchedule() throws {
        let state = try onLeave(leave("10:00", "11:00", 10))
        let later = WorkSchedule(start: clock("13:00"), end: clock("20:00"), lunch: nil)
        let changed = try sending(.changeSchedule(later), to: state)
        let today = try #require(snapshot(of: changed, at: standardDay(13, 30)).today)

        #expect(today.status == .working)
        #expect(today.earnings?.cap == 900)
    }
}
