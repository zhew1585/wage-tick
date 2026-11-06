import Foundation
import Testing
import WageCore

// 单日详情里的编辑入口 (PRD 4.6.1 可编辑内容、F11)：哪些能改、不能改时的原因、表单预填与预览起点。
// 标准算例，「今天」是 2026 年 2 月 11 日 (周三) 15:00。

private func feb(_ day: Int) -> LocalDate {
    LocalDate(year: 2026, month: 2, day: day)
}

private func editing(_ date: LocalDate, _ edit: DayEdit, in state: AppState) throws -> AppState {
    try apply(.editDay(date, edit), to: state, at: standardDay(15, 0)).state
}

private func entries(_ state: AppState, _ date: LocalDate) throws -> DayEditing {
    try #require(snapshot(of: state, at: standardDay(15, 0)).historyDay(date)).detail.editing
}

private let blockedFuture = "还没到这一天，只能请假或设置单日覆盖"
private let blockedRest = "今天本来就不上班"

@Suite("历史编辑：编辑入口")
struct HistoryEditEntryTests {
    @Test("过去的应出勤日：扣钱、请假、白干都能改，预览起点为这天的结算；单日覆盖可改成不上班日")
    func pastAttendanceDay() throws {
        let editing = try entries(try onboarded(), feb(4))

        #expect(editing.deduction.content?.capText == "¥1000")
        #expect(editing.deduction.content?.warning == nil)
        guard case .available(let form) = editing.leave else {
            Issue.record("期望能请假")
            return
        }
        #expect(form.current == nil)
        #expect(form.canRequest)
        #expect(form.summary == [
            StatItem(title: "当日计划", value: "10:00–18:00"),
            StatItem(title: "请假扣薪", value: "¥0"),
            StatItem(title: "结算", value: "¥1000"),
        ])
        #expect(editing.unpaidWork == .available(UnpaidWorkInput(start: TimeOfDay(hour: 18, minute: 0), end: TimeOfDay(hour: 19, minute: 0))))
        #expect(editing.overrideButton == EditButton(title: "改成不上班日", command: .editDay(feb(4), .setOverride(.dayOff))))
    }

    @Test("AC-CAL-04 下周三：只能请假和设置单日覆盖，扣钱和白干不可用并说明原因；请假汇总为预计结算")
    func futureDay() throws {
        let editing = try entries(try onboarded(), feb(18))

        #expect(editing.deduction == .unavailable(reason: blockedFuture))
        #expect(editing.unpaidWork == .unavailable(reason: blockedFuture))
        guard case .available(let form) = editing.leave else {
            Issue.record("期望能请假")
            return
        }
        #expect(form.summary.last == StatItem(title: "预计结算", value: "¥1000"))
        #expect(editing.overrideButton.title == "改成不上班日")
    }

    @Test("#8 休息日：扣钱、请假不可用，提示【今天本来就不上班】；白干可补记 (被迫营业)；单日覆盖可改成上班日")
    func restDay() throws {
        let editing = try entries(try onboarded(), feb(7))

        #expect(editing.deduction == .unavailable(reason: blockedRest))
        #expect(editing.leave == .unavailable(reason: blockedRest))
        #expect(editing.unpaidWork.isAvailable)
        #expect(editing.overrideButton == EditButton(title: "改成上班日", command: .editDay(feb(7), .setOverride(.attendanceDay))))
    }

    @Test("已有单日覆盖的日子：按钮为撤销单日覆盖")
    func overriddenDay() throws {
        let state = try editing(feb(7), .setOverride(.attendanceDay), in: try onboarded())
        let editing = try entries(state, feb(7))

        #expect(editing.overrideButton == EditButton(title: "撤销单日覆盖", command: .editDay(feb(7), .clearOverride)))
        #expect(editing.deduction.isAvailable)
    }

    @Test("今天：预览起点为今日上限，请假汇总为今日上限，与面板的请假表单一致")
    func today() throws {
        let state = try onboarded()
        let editing = try entries(state, feb(11))
        let panelForm = snapshot(of: state, at: standardDay(15, 0)).leaveForm

        #expect(editing.deduction.content?.capText == "¥1000")
        #expect(editing.deduction.content?.warning == nil)
        #expect(editing.leave == panelForm.map(EditEntry.available))
    }

    @Test("已请全天假的日子：请假表单带出已有的请假，不能再新请")
    func existingLeave() throws {
        let state = try editing(feb(4), .setLeave(fullDayLeave(30)), in: try onboarded())
        guard case .available(let form) = try entries(state, feb(4)).leave else {
            Issue.record("期望能请假")
            return
        }

        #expect(form.current == fullDayLeave(30))
        #expect(form.currentText == "已请全天假 · 扣薪 30.00%")
        #expect(!form.canRequest)
        #expect(form.summary == [
            StatItem(title: "当日计划", value: "全天请假"),
            StatItem(title: "请假扣薪", value: "−¥300"),
            StatItem(title: "结算", value: "¥700"),
        ])
    }

    @Test("白干段逐段列出编号与预填时段；计时中的那段不能改")
    func unpaidWorkItems() throws {
        var state = try editing(feb(11), .addUnpaidWork(UnpaidWorkInput(start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 9, minute: 15))), in: try onboarded())
        state = try apply(.startUnpaidWork, to: state, at: standardDay(18, 0)).state
        let items = try #require(snapshot(of: state, at: standardDay(19, 0)).historyDay(feb(11))).detail.editing.unpaidWorkItems

        #expect(items.map(\.index) == [0, 1])
        #expect(items.map(\.line.title) == ["08:00 – 09:15", "18:00 起"])
        #expect(items.map(\.input) == [UnpaidWorkInput(start: TimeOfDay(hour: 8, minute: 0), end: TimeOfDay(hour: 9, minute: 15)), nil])
    }

    @Test("历史月份带出该月月薪，供改月薪时预填")
    func monthSalary() throws {
        let month = try #require(snapshot(of: try onboarded(), at: standardDay(15, 0)).historyMonth(YearMonth(year: 2026, month: 2)))

        #expect(month.salaryText == "¥20000 → 日薪 ¥1000")
        #expect(month.monthlySalary == 20000)
    }
}

@Suite("历史编辑：扣钱预览")
struct HistoryDeductionPreviewTests {
    @Test("补记过去的日子：预览写「结算 ¥1000」；今天仍是「今日上限」")
    func previewTitle() throws {
        let snap = snapshot(of: try onboarded(), at: standardDay(15, 0))
        let past = try #require(snap.historyDay(LocalDate(year: 2026, month: 2, day: 4))?.detail.editing.deduction.content)
        let today = try #require(snap.panel?.deductionEntry)

        #expect(past.previewLine(to: nil) == "结算 ¥1000")
        #expect(today.previewLine(to: nil) == "今日上限 ¥1000")
    }
}
