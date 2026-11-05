import Foundation
import Testing
import WageCore

// 历史的展示字段 (设计稿 P4 月列表、P5 月日历与单日详情 · 760)：月份标签、短标题汇总、月薪条、格子金额与小字、
// 当天结算的算式、白干段的倒贴。文字都在核心格式化好，外壳原样展示。
// 标准算例：2026 年 2 月只按双休 20 个应出勤日，月薪 20000，日薪 1000，作息 10:00 至 18:00。

private let february = YearMonth(year: 2026, month: 2)

private func feb(_ day: Int) -> LocalDate {
    LocalDate(year: 2026, month: 2, day: day)
}

private func applied(_ command: Command, to state: AppState, at now: Moment) throws -> AppState {
    try apply(command, to: state, at: now).state
}

private func editing(_ date: LocalDate, _ edit: DayEdit, in state: AppState, at now: Moment = standardDay(15, 0)) throws -> AppState {
    try apply(.editDay(date, edit), to: state, at: now).state
}

private let lateFifty = Command.addDeduction(DeductionInput(amount: .fixed(50), reason: .late, note: ""))

/// 2 月 2 日 (周一) 安装，4 日迟到扣 50，6 日请下午假 (50%)，9 日 18:00 至 19:30 白干。
private func februaryWithRecords() throws -> AppState {
    var state = try onboarded(at: moment(2026, 2, 2, 9, 0))
    state = try applied(lateFifty, to: state, at: moment(2026, 2, 4, 15, 0))
    state = try applied(.requestLeave(Leave(period: .afternoon, deductionPercent: 50)), to: state, at: moment(2026, 2, 6, 9, 0))
    state = try applied(.startUnpaidWork, to: state, at: moment(2026, 2, 9, 18, 0))
    return try applied(.stopUnpaidWork, to: state, at: moment(2026, 2, 9, 19, 30))
}

private func month(_ snap: Snapshot, _ month: YearMonth = february) throws -> HistoryMonth {
    try #require(snap.historyMonth(month))
}

private func day(_ snap: Snapshot, _ date: LocalDate) throws -> HistoryDay {
    try #require(snap.historyDay(date))
}

@Suite("历史展示：月列表")
struct HistoryMonthDisplayTests {
    @Test("月份标签：本月「本月 · 进行中」，安装当月「安装当月」，其余没有")
    func badges() throws {
        let snap = snapshot(of: try onboarded(), at: moment(2026, 4, 15, 15, 0))

        #expect(snap.historyMonths().map(\.badge) == ["本月 · 进行中", nil, "安装当月"])
    }

    @Test("安装当月就是本月时只标「本月 · 进行中」")
    func installedThisMonth() throws {
        let snap = snapshot(of: try onboarded(), at: standardDay(15, 0))

        #expect(snap.historyMonths().map(\.badge) == ["本月 · 进行中"])
    }

    @Test("3 月查看 2 月：结算总额 ¥19450 单独放，下面应出勤 20 天、扣款 ¥550 (标亏钱色)、请假 0.5 天、白干 1h30m")
    func figures() throws {
        let summary = try month(snapshot(of: try februaryWithRecords(), at: moment(2026, 3, 10, 15, 0))).summary

        #expect(summary.total == "¥19450")
        #expect(summary.figures == [
            HistoryFigure(title: "应出勤", value: "20 天"),
            HistoryFigure(title: "扣款", value: "¥550", isLoss: true),
            HistoryFigure(title: "请假", value: "0.5 天"),
            HistoryFigure(title: "白干", value: "1h30m"),
        ])
    }

    @Test("没有扣款和白干：扣款 ¥0 不标亏钱色，白干 0m")
    func zeroFigures() throws {
        let summary = try month(snapshot(of: try onboarded(at: moment(2026, 2, 2, 9, 0)), at: moment(2026, 3, 2, 9, 0))).summary

        #expect(summary.figures.map(\.value) == ["20 天", "¥0", "0 天", "0m"])
        #expect(summary.figures.allSatisfy { !$0.isLoss })
    }

    @Test("白干时长：不满 1 小时只写分钟，满 1 小时分钟补足两位，如 45m、2h05m")
    func durations() throws {
        var state = try onboarded(at: moment(2026, 2, 2, 9, 0))
        state = try editing(feb(3), .addUnpaidWork(UnpaidWorkInput(start: TimeOfDay(hour: 18, minute: 0), end: TimeOfDay(hour: 18, minute: 45))), in: state)
        #expect(try month(snapshot(of: state, at: standardDay(15, 0))).summary.figures.last?.value == "45m")

        state = try editing(feb(4), .addUnpaidWork(UnpaidWorkInput(start: TimeOfDay(hour: 18, minute: 0), end: TimeOfDay(hour: 19, minute: 20))), in: state)
        #expect(try month(snapshot(of: state, at: standardDay(15, 0))).summary.figures.last?.value == "2h05m")
    }
}

@Suite("历史展示：月日历")
struct HistoryCalendarDisplayTests {
    @Test("月薪条：本月「本月月薪 · 应出勤 20 天」「¥20000 → 日薪 ¥1000」；往月写几月月薪")
    func salaryRow() throws {
        let snap = snapshot(of: try onboarded(at: moment(2026, 2, 2, 9, 0)), at: moment(2026, 3, 10, 15, 0))

        #expect(try month(snap, YearMonth(year: 2026, month: 3)).salaryCaption == "本月月薪 · 应出勤 22 天")
        #expect(try month(snap).salaryCaption == "2月月薪 · 应出勤 20 天")
        #expect(try month(snap).salaryText == "¥20000 → 日薪 ¥1000")
    }

    @Test("AC-CAL-01 周六改成上班日后应出勤 21 天，日薪 ¥952.381")
    func salaryRowAfterOverride() throws {
        let state = try editing(feb(7), .setOverride(.attendanceDay), in: try onboarded(at: moment(2026, 2, 2, 9, 0)))
        let snap = snapshot(of: state, at: standardDay(15, 0))

        #expect(try month(snap).salaryCaption == "本月月薪 · 应出勤 21 天")
        #expect(try month(snap).salaryText == "¥20000 → 日薪 ¥952.381")
    }

    @Test("月小结：已结算 (同结算总额)、扣款、请假、白干")
    func footer() throws {
        let snap = snapshot(of: try februaryWithRecords(), at: moment(2026, 2, 11, 15, 0))

        #expect(try month(snap).footer == [
            HistoryFigure(title: "已结算", value: "¥7021.4286"),
            HistoryFigure(title: "扣款", value: "¥550", isLoss: true),
            HistoryFigure(title: "请假", value: "0.5 天"),
            HistoryFigure(title: "白干", value: "1h30m"),
        ])
    }

    @Test("格子金额取整到元：已过的应出勤日写结算，今天写今日已赚，未来和休息日不写")
    func amounts() throws {
        let snap = snapshot(of: try februaryWithRecords(), at: standardDay(15, 0))

        #expect(try [3, 4, 6, 7, 11, 12].map { try day(snap, feb($0)).amountText } == ["¥1000", "¥950", "¥500", nil, "¥571", nil])
    }

    @Test("日薪有零头时格子金额四舍五入：952.381 写 ¥952")
    func roundedAmount() throws {
        let state = try editing(feb(7), .setOverride(.attendanceDay), in: try onboarded(at: moment(2026, 2, 2, 9, 0)))

        #expect(try day(snapshot(of: state, at: standardDay(15, 0)), feb(9)).amountText == "¥952")
    }

    @Test("格子小字：请假写时段，改成不上班写「改休」，改成上班写「改班」，其余没有")
    func tags() throws {
        var state = try onboarded(at: moment(2026, 2, 2, 9, 0))
        state = try editing(feb(12), .requestLeave(Leave(period: .afternoon, deductionPercent: 50)), in: state)
        state = try editing(feb(13), .requestLeave(Leave(period: .fullDay, deductionPercent: 100)), in: state)
        state = try editing(feb(16), .setOverride(.dayOff), in: state)
        state = try editing(feb(14), .setOverride(.attendanceDay), in: state)
        let snap = snapshot(of: state, at: standardDay(15, 0))

        #expect(try [12, 13, 16, 14, 10].map { try day(snap, feb($0)).tag } == ["下午", "全天", "改休", "改班", nil])
    }

    @Test("改成上班的日子按上班日的颜色类型 (满勤、未到……)；只有改成不上班的日子是单日覆盖，图例写「改成不上班」")
    func overrideKinds() throws {
        var state = try onboarded(at: moment(2026, 2, 2, 9, 0))
        state = try editing(feb(7), .setOverride(.attendanceDay), in: state)
        state = try editing(feb(14), .setOverride(.attendanceDay), in: state)
        state = try editing(feb(16), .setOverride(.dayOff), in: state)
        let snap = snapshot(of: state, at: standardDay(15, 0))

        #expect(try [7, 14, 16].map { try day(snap, feb($0)).kind } == [.fullAttendance, .upcoming, .override])
        #expect(CalendarDayKind.legend.map(\.label) == ["满勤", "被扣钱", "请假", "改成不上班"])
    }
}

@Suite("历史展示：单日详情")
struct HistoryDayDisplayTests {
    @Test("当天结算：标题过去「当天结算」、今天「今日已赚」、未来「预计结算」，休息日没有")
    func headline() throws {
        let snap = snapshot(of: try onboarded(at: moment(2026, 2, 2, 9, 0)), at: standardDay(15, 0))

        #expect(try [10, 11, 12, 7].map { try day(snap, feb($0)).detail.headlineTitle } == ["当天结算", "今日已赚", "预计结算", nil])
    }

    @Test("算式：有扣钱写「日薪 1000 − 扣款 50」，有请假加「请假 500」；没扣也没请假不写")
    func breakdown() throws {
        var state = try onboarded(at: moment(2026, 2, 2, 9, 0))
        state = try editing(feb(4), .addDeduction(DeductionInput(amount: .fixed(50), reason: .late, note: "")), in: state)
        state = try editing(feb(5), .requestLeave(Leave(period: .afternoon, deductionPercent: 50)), in: state)
        state = try editing(feb(5), .addDeduction(DeductionInput(amount: .fixed(30), reason: .late, note: "")), in: state)
        let snap = snapshot(of: state, at: standardDay(15, 0))

        #expect(try day(snap, feb(4)).detail.breakdown == "日薪 1000 − 扣款 50")
        #expect(try day(snap, feb(5)).detail.breakdown == "日薪 1000 − 请假 500 − 扣款 30")
        #expect(try day(snap, feb(3)).detail.breakdown == nil)
        #expect(try day(snap, feb(7)).detail.breakdown == nil)
    }

    @Test("判定来源 (设计稿)：不在节假日表里的周一至周五为「工作日」，周六日为「双休」")
    func source() throws {
        let snap = snapshot(of: try onboarded(at: moment(2026, 2, 2, 9, 0)), at: standardDay(15, 0))

        #expect(try [10, 7].map { try day(snap, feb($0)).detail.source.label } == ["工作日", "双休"])
    }

    @Test("PRD 4.4.3 算例：白干段写「18:00 – 19:30」「1h30m」，这一段倒贴 ¥214.2857")
    func unpaidWorkLine() throws {
        let detail = try day(snapshot(of: try februaryWithRecords(), at: standardDay(15, 0)), feb(9)).detail

        #expect(detail.unpaidWork == [HistoryLine(title: "18:00 – 19:30", detail: nil, value: "1h30m")])
        #expect(detail.editing.unpaidWorkItems.map(\.loss) == ["倒贴 ¥214.2857"])
    }
}
