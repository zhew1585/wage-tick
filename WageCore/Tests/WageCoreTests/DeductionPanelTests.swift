import Foundation
import Testing
import WageCore

@Suite("今天扣钱了：面板展示")
struct DeductionPanelTests {
    @Test("AC-HOME-04 有扣钱 50 元，18:30 打开：主数字 ¥950.0000，统计行扣款 −¥50，无倒计时")
    func offWorkWithDeduction() throws {
        // 2026-02-11 是 2 月第 8 个应出勤日：前 7 天 7000 + 今日结算 950。
        let fined = try recordingDeduction(.fixed(50), on: try onboarded(), at: standardDay(15, 0))
        let body = try attendancePanel(fined, at: standardDay(18, 30))

        #expect(body.headline == "¥950.0000")
        #expect(body.stats == [
            StatItem(title: "今日结算", value: "¥950"),
            StatItem(title: "今日扣款", value: "−¥50"),
            StatItem(title: "本月累计", value: "¥7950"),
        ])
    }

    @Test("PRD 4.3.4 上班中有扣钱：小字今日上限按扣款后的数显示，统计行为倒计时、扣款合计与本月累计")
    func workingWithDeduction() throws {
        let fined = try recordingDeduction(.fixed(50), on: try onboarded(), at: standardDay(15, 0))
        let body = try attendancePanel(fined, at: standardDay(15, 0))

        #expect(body.headline == "¥542.8571")
        #expect(body.caption == "满勤日薪 ¥1000 · 时薪 ¥142.8571")
        #expect(body.stats.map(\.title) == ["距离下班", "今日扣款", "本月累计"])
        #expect(body.stats[1].value == "−¥50")
    }

    @Test("AC-FINE-04 同一天记 2 笔：明细分别展示原因、金额与说明")
    func detailsListedSeparately() throws {
        var state = try onboarded()
        state = try recordingDeduction(.fixed(50), reason: .late, note: "地铁故障", on: state, at: standardDay(10, 30))
        state = try recordingDeduction(.percentOfDailyWage(10), on: state, at: standardDay(15, 0))
        let items = try attendancePanel(state, at: standardDay(15, 0)).deductions

        #expect(items.map(\.title) == ["迟到", "扣钱"])
        #expect(items.map(\.amount) == ["−¥50", "−¥100"])
        #expect(items.map(\.detail) == ["地铁故障", "日薪 10%"])
    }

    @Test("PRD 4.4.1 #2 按百分比的明细：金额按当月日薪折算后截掉末尾 0，说明带比例与备注")
    func percentDetailWithNote() throws {
        // 2026 年 5 月日薪 = 20000 ÷ 21，12.5% 为 119.047619…
        let fined = try recordingDeduction(
            .percentOfDailyWage(Decimal(string: "12.5")!), reason: .leftEarly, note: "提前走", on: try onboarded(), at: moment(2026, 5, 6, 15, 0)
        )
        let item = try #require(try attendancePanel(fined, at: moment(2026, 5, 6, 15, 0)).deductions.first)

        #expect(item.title == "早退")
        #expect(item.amount == "−¥119.0476")
        #expect(item.detail == "日薪 12.5% · 提前走")
    }

    @Test("没有扣钱时：无明细、无提示，统计行扣款显示 ¥0")
    func noDeduction() throws {
        let body = try attendancePanel(try onboarded(), at: standardDay(18, 30))

        #expect(body.deductions.isEmpty)
        #expect(body.notice == nil)
        #expect(body.stats.contains(StatItem(title: "今日扣款", value: "¥0")))
    }

    @Test("AC-FINE-05 记 1200 元：提示【今天已经白干了，再扣就倒贴了】，今日上限 ¥0")
    func overDeductionNotice() throws {
        let fined = try recordingDeduction(.fixed(1200), on: try onboarded(), at: standardDay(15, 0))
        let body = try attendancePanel(fined, at: standardDay(15, 0))
        let entry = try #require(snapshot(of: fined, at: standardDay(15, 0)).panel?.deductionEntry)

        #expect(body.notice == "今天已经白干了，再扣就倒贴了")
        #expect(entry.capText == "¥0")
        #expect(entry.warning == "今天已经白干了，再扣就倒贴了")
    }

    @Test("PRD 4.3.5 #6 当日扣款正好等于日薪：今日上限 0，但还没超过日薪，不提示")
    func exactlyDailyWageHasNoNotice() throws {
        let fined = try recordingDeduction(.fixed(1000), on: try onboarded(), at: standardDay(15, 0))

        #expect(try attendancePanel(fined, at: standardDay(15, 0)).notice == nil)
    }
}

@Suite("今天扣钱了：入口与表单预览")
struct DeductionEntryTests {
    @Test("AC-FINE-07 周六打开面板：没有「今天扣钱了」入口")
    func noEntryOnRestDay() throws {
        let panel = try #require(snapshot(of: try onboarded(), at: moment(2026, 2, 14, 11, 0)).panel)

        #expect(panel.deductionEntry == nil)
    }

    @Test("F5 应出勤日全天都有入口：未上班、上班中、午休中、已下班", arguments: [(9, 30), (11, 0), (12, 30), (18, 30)])
    func entryOnAttendanceDay(time: (Int, Int)) throws {
        let panel = try #require(snapshot(of: try onboarded(), at: standardDay(time.0, time.1)).panel)

        #expect(panel.deductionEntry != nil)
    }

    @Test("F5 实时预览「今日上限 ¥x → ¥y」：拿草稿试算后的快照与当前快照对比")
    func previewLine() throws {
        let state = try onboarded()
        let draft = DeductionInput(amount: .percentOfDailyWage(10), reason: nil, note: "")
        let drafted = try apply(.addDeduction(draft), to: state, at: standardDay(15, 0)).state
        let current = try #require(snapshot(of: state, at: standardDay(15, 0)).panel?.deductionEntry)
        let preview = try #require(snapshot(of: drafted, at: standardDay(15, 0)).panel?.deductionEntry)

        #expect(current.previewLine(to: preview) == "今日上限 ¥1000 → ¥900")
        #expect(current.previewLine(to: nil) == "今日上限 ¥1000")
        #expect(preview.warning == nil)
    }

    @Test("F5 编辑时的预览：以当前今日上限为起点，按改后的数值算终点")
    func previewWhileEditing() throws {
        let fined = try recordingDeduction(.fixed(50), on: try onboarded(), at: standardDay(15, 0))
        let id = try #require(try attendancePanel(fined, at: standardDay(15, 0)).deductions.first?.id)
        let edit = DeductionInput(amount: .fixed(200), reason: nil, note: "")
        let edited = try apply(.editDeduction(id: id, edit), to: fined, at: standardDay(15, 0)).state
        let current = try #require(snapshot(of: fined, at: standardDay(15, 0)).panel?.deductionEntry)
        let preview = try #require(snapshot(of: edited, at: standardDay(15, 0)).panel?.deductionEntry)

        #expect(current.previewLine(to: preview) == "今日上限 ¥950 → ¥800")
    }
}
