import Foundation
import Testing
import WageCore

// 请假表单 (PRD F6)：时段校验、默认比例、时间条与汇总。作息同 LeaveTests：10:00 至 18:00、饭点 12:00 至 13:00。

/// 标准算例今天 09:00 的请假表单。
private func leaveForm(_ state: AppState? = nil, schedule: WorkSchedule = standardSchedule) throws -> LeaveForm {
    try #require(snapshot(of: try state ?? onboarded(schedule: schedule), at: standardDay(9, 0)).leaveForm)
}

private func range(_ start: String, _ end: String) -> LeaveRange {
    LeaveRange(start: clock(start), end: clock(end))
}

@Suite("请假：时段校验")
struct LeaveRangeValidationTests {
    @Test("时段要在计划上下班之内、结束晚于开始", arguments: [
        ("09:00", "11:00"), ("17:00", "18:30"), ("14:00", "14:00"), ("16:00", "14:00"),
    ])
    func outsideWorkHours(start: String, end: String) throws {
        #expect(throws: CommandError.leaveOutsideWorkHours) {
            try apply(.setLeave(leave(start, end, 10)), to: try onboarded(), at: standardDay(9, 0))
        }
        #expect(CommandError.leaveOutsideWorkHours.message == "请假要在上下班时间之内")
    }

    @Test("开始、结束对齐到 10 分钟", arguments: [("14:05", "16:00"), ("14:00", "15:59")])
    func offStep(start: String, end: String) throws {
        #expect(throws: CommandError.leaveOffStep) {
            try apply(.setLeave(leave(start, end, 10)), to: try onboarded(), at: standardDay(9, 0))
        }
        #expect(CommandError.leaveOffStep.message == "请假时间按 10 分钟取整")
    }

    @Test("计划上下班、饭点边界不在 10 分钟刻度上时也可以对上 (09:05 至 18:00，饭点 12:05 至 13:05)")
    func anchorsOffTheGrid() throws {
        let schedule = WorkSchedule(
            start: clock("09:05"), end: clock("18:00"), lunch: LunchBreak(start: clock("12:05"), end: clock("13:05"))
        )
        let state = try onboarded(schedule: schedule)

        #expect(throws: Never.self) { try apply(.setLeave(leave("09:05", "12:05", 10)), to: state, at: standardDay(9, 0)) }
        #expect(throws: Never.self) { try apply(.setLeave(leave("13:05", "14:00", 10)), to: state, at: standardDay(9, 0)) }
        // 12:00 至 12:05 两端都合规，但不到 10 分钟。
        #expect(throws: CommandError.leaveTooShort) {
            try apply(.setLeave(leave("12:00", "12:05", 10)), to: state, at: standardDay(9, 0))
        }
        #expect(CommandError.leaveTooShort.message == "请假至少 10 分钟")
    }

    @Test("10 分钟正好可以；历史里的日子按那天的作息校验")
    func minimumAndPastDay() throws {
        let state = try onboarded()

        #expect(throws: Never.self) { try apply(.setLeave(leave("14:00", "14:10", 10)), to: state, at: standardDay(9, 0)) }
        #expect(throws: CommandError.leaveOutsideWorkHours) {
            try apply(.editDay(LocalDate(year: 2026, month: 2, day: 10), .setLeave(leave("09:00", "10:00", 10))), to: state, at: standardDay(9, 0))
        }
    }

    @Test("AC-LEAVE-08 扣薪比例填 120%：提示【扣薪比例要在 0% 到 100% 之间】", arguments: [Decimal(120), Decimal(-1), Decimal(string: "100.01")!])
    func percentOutOfRangeIsRejected(percent: Decimal) throws {
        #expect(throws: CommandError.leavePercentOutOfRange) {
            try apply(.setLeave(secondHalfLeave(percent)), to: try onboarded(), at: standardDay(9, 0))
        }
        #expect(CommandError.leavePercentOutOfRange.message == "扣薪比例要在 0% 到 100% 之间")
    }

    @Test("PRD 4.3.5 #22 扣薪比例为空也提示同一条；0% 和 100% 可以保存")
    func percentBoundaries() throws {
        #expect(Validation.leaveDeductionPercent(nil) == .leavePercentOutOfRange)
        #expect(Validation.leaveDeductionPercent(0) == nil)
        #expect(Validation.leaveDeductionPercent(100) == nil)
        #expect(throws: Never.self) { try onLeave(fullDayLeave(0)) }
        #expect(throws: Never.self) { try onLeave(fullDayLeave(100)) }
    }

    @Test("PRD 4.3.5 #8 休息日不能请假：提示【今天本来就不上班】，表单不可用")
    func restDayCannotRequestLeave() throws {
        let state = try onboarded()
        let saturday = moment(2026, 2, 14, 11, 0)

        #expect(throws: CommandError.notAttendanceDay) { try apply(.setLeave(fullDayLeave(100)), to: state, at: saturday) }
        #expect(CommandError.notAttendanceDay.message == "今天本来就不上班")
        #expect(snapshot(of: state, at: saturday).leaveForm == nil)
    }
}

@Suite("请假：默认扣薪比例")
struct LeaveDefaultPercentTests {
    @Test("AC-LEAVE-07 按请掉的有效工时占标准工时带出，饭点不算工时，四舍五入到 2 位", arguments: [
        ("10:00", "18:00", "100"),
        ("10:00", "12:00", "28.57"),
        ("13:00", "18:00", "71.43"),
        ("14:00", "16:00", "28.57"),
        // 跨过饭点：11:00 至 14:00 只请掉 2 小时工时。
        ("11:00", "14:00", "28.57"),
        ("12:10", "12:50", "0"),
        ("14:00", "14:10", "2.38"),
    ])
    func proportional(start: String, end: String, expected: String) throws {
        #expect(try leaveForm().bar.defaultPercent(for: range(start, end)) == Decimal(string: expected)!)
    }

    @Test("请掉全部工时 (饭点紧贴计划下班时请到饭点开始) 即全天：100%")
    func allWorkingHoursIsFullDay() throws {
        let schedule = WorkSchedule(
            start: clock("10:00"), end: clock("18:00"), lunch: LunchBreak(start: clock("17:00"), end: clock("18:00"))
        )

        #expect(try leaveForm(schedule: schedule).bar.defaultPercent(for: range("10:00", "17:00")) == 100)
    }

    @Test("关闭饭点：按整段计 (10:00 至 18:00 请 14:00 至 16:00 为 25%)")
    func withoutLunch() throws {
        let schedule = WorkSchedule(start: clock("10:00"), end: clock("18:00"), lunch: nil)

        #expect(try leaveForm(schedule: schedule).bar.defaultPercent(for: range("14:00", "16:00")) == 25)
    }
}

@Suite("请假：时间条")
struct LeaveBarTests {
    @Test("快捷时段：全天、前半天、后半天 (以饭点为分界)")
    func quickPicks() throws {
        let picks = try leaveForm().bar.quickPicks

        #expect(picks.map(\.title) == ["全天", "前半天", "后半天"])
        #expect(picks.map(\.range) == [range("10:00", "18:00"), range("10:00", "12:00"), range("13:00", "18:00")])
        #expect(try leaveForm().bar.fullDay == range("10:00", "18:00"))
    }

    @Test("关闭饭点时前半天、后半天以中点为分界")
    func quickPicksWithoutLunch() throws {
        let schedule = WorkSchedule(start: clock("10:00"), end: clock("18:00"), lunch: nil)

        #expect(try leaveForm(schedule: schedule).bar.quickPicks.map(\.range) == [
            range("10:00", "18:00"), range("10:00", "14:00"), range("14:00", "18:00"),
        ])
    }

    @Test("饭点、刻度与时刻文字：10:00 至 18:00 每 10 分钟一根刻度，每 2 小时一个时刻")
    func ticksAndLabels() throws {
        let bar = try leaveForm().bar

        #expect([bar.lunch?.start, bar.lunch?.end] == [0.25, 0.375])
        #expect(bar.ticks.count == 49)
        #expect(bar.ticks.filter(\.isHour).count == 9)
        #expect(bar.labels.map(\.text) == ["10:00", "12:00", "14:00", "16:00", "18:00"])
        #expect(bar.labels.map(\.position) == [0, 0.25, 0.5, 0.75, 1])
    }

    @Test("时刻文字随跨度调整，离结尾太近的不写：16:00 至 23:00 为 16、18、20、23 点", arguments: [
        ("16:00", "23:00", ["16:00", "18:00", "20:00", "23:00"]),
        ("09:00", "18:00", ["09:00", "12:00", "15:00", "18:00"]),
        ("09:05", "12:00", ["09:05", "10:00", "11:00", "12:00"]),
    ])
    func labelsAdaptToSpan(start: String, end: String, expected: [String]) throws {
        let schedule = WorkSchedule(start: clock(start), end: clock(end), lunch: nil)

        #expect(try leaveForm(schedule: schedule).bar.labels.map(\.text) == expected)
    }

    @Test("时段说明：时段与请掉的有效工时", arguments: [
        ("14:00", "16:00", "14:00 – 16:00", "2 小时"),
        ("11:00", "14:00", "11:00 – 14:00", "2 小时"),
        ("14:00", "14:40", "14:00 – 14:40", "40 分钟"),
        ("14:00", "15:30", "14:00 – 15:30", "1 小时 30 分"),
    ])
    func title(start: String, end: String, text: String, duration: String) throws {
        let title = try leaveForm().bar.title(of: range(start, end))

        #expect([title.range, title.duration] == [text, duration])
    }

    @Test("拖把手吸附到 10 分钟，不越过另一个把手，至少留 10 分钟")
    func draggingHandles() throws {
        let bar = try leaveForm().bar
        let selected = range("14:00", "16:00")
        // 每分钟占 1/480。
        let at = { (minutes: Double) in (minutes - 600) / 480 }

        #expect(bar.dragging(.start, of: selected, to: at(14 * 60 + 7)) == range("14:10", "16:00"))
        #expect(bar.dragging(.start, of: selected, to: at(17 * 60)) == range("15:50", "16:00"))
        #expect(bar.dragging(.start, of: selected, to: -0.2) == range("10:00", "16:00"))
        #expect(bar.dragging(.end, of: selected, to: at(12 * 60 + 2)) == range("14:00", "14:10"))
        #expect(bar.dragging(.end, of: selected, to: 1.3) == range("14:00", "18:00"))
        #expect(bar.position(of: clock("14:00")) == 0.5)
    }

    @Test("拖把手可以吸附到不在刻度上的计划上班 (09:05)")
    func draggingSnapsToAnchor() throws {
        let schedule = WorkSchedule(start: clock("09:05"), end: clock("18:00"), lunch: .default)
        let bar = try leaveForm(schedule: schedule).bar

        #expect(bar.dragging(.start, of: range("10:00", "11:00"), to: 0) == range("09:05", "11:00"))
    }

    @Test("拖选中的一段整体平移，不出计划上下班")
    func movingRange() throws {
        let bar = try leaveForm().bar
        let selected = range("14:00", "16:00")

        #expect(bar.moving(selected, by: 30.0 / 480) == range("14:30", "16:30"))
        #expect(bar.moving(selected, by: 33.0 / 480) == range("14:30", "16:30"))
        #expect(bar.moving(selected, by: 0.9) == range("16:00", "18:00"))
        #expect(bar.moving(selected, by: -0.9) == range("10:00", "12:00"))
    }
}

@Suite("请假：表单汇总")
struct LeaveFormSummaryTests {
    @Test("F6 还没请假：今天上班为作息原样，能新请")
    func summaryWithoutLeave() throws {
        let form = try leaveForm()

        #expect(form.current == nil)
        #expect(form.currentText == nil)
        #expect(form.canRequest)
        #expect(form.summary == [
            StatItem(title: "今天上班", value: "10:00–18:00"),
            StatItem(title: "请假扣薪", value: "¥0"),
            StatItem(title: "今日上限", value: "¥1000"),
        ])
    }

    @Test("F6 请 14:00 至 16:00 (28.57%)：今天上班两段，请假扣薪 −¥285.70，今日上限 ¥714.30，已请假时只能修改")
    func summaryWithMiddleLeave() throws {
        let state = try onLeave(leave("14:00", "16:00", Decimal(string: "28.57")!))
        let form = try leaveForm(state)

        #expect(form.current == leave("14:00", "16:00", Decimal(string: "28.57")!))
        #expect(form.currentText == "已请假 14:00–16:00 · 扣薪 28.57%")
        #expect(!form.canRequest)
        #expect(form.deductionText == "= ¥285.70")
        #expect(form.summary == [
            StatItem(title: "今天上班", value: "10:00–14:00、16:00–18:00"),
            StatItem(title: "请假扣薪", value: "−¥285.70"),
            StatItem(title: "今日上限", value: "¥714.30"),
        ])
    }

    @Test("F6 请后半天 50%：今天上班 10:00–12:00")
    func summaryWithSecondHalf() throws {
        let form = try leaveForm(try onLeave(secondHalfLeave(50)))

        #expect(form.currentText == "已请假 13:00–18:00 · 扣薪 50.00%")
        #expect(form.summary.first == StatItem(title: "今天上班", value: "10:00–12:00"))
    }

    @Test("F6 全天请假 12.5%：今天上班为全天请假，比例固定 2 位小数")
    func summaryWithFullDayLeave() throws {
        let form = try leaveForm(try onLeave(fullDayLeave(Decimal(string: "12.5")!)))

        #expect(form.currentText == "已请全天假 · 扣薪 12.50%")
        #expect(!form.canRequest)
        #expect(form.summary == [
            StatItem(title: "今天上班", value: "全天请假"),
            StatItem(title: "请假扣薪", value: "−¥125"),
            StatItem(title: "今日上限", value: "¥875"),
        ])
    }
}
