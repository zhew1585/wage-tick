import Foundation
import Testing
import WageCore

/// 取应出勤日面板；不是应出勤日面板时测试失败。
func attendancePanel(_ state: AppState, at now: Moment) throws -> AttendancePanel {
    let panel = try #require(snapshot(of: state, at: now).panel)
    guard case .attendance(let body) = panel.body else {
        Issue.record("期望应出勤日面板，实际为 \(panel.body)")
        throw PanelError.wrongBody
    }
    return body
}

enum PanelError: Error { case wrongBody }

@Suite("今日概览：上班中")
struct TodayPanelWorkingTests {
    @Test("AC-HOME-01 15:00 打开：今日已赚 ¥571.4286，【已工作 4 / 7 小时】【57.14%】")
    func progressAt1500() throws {
        let state = try onboarded()
        let panel = try #require(snapshot(of: state, at: standardDay(15, 0)).panel)
        let body = try attendancePanel(state, at: standardDay(15, 0))

        #expect(panel.statusLabel == "上班中")
        #expect(body.headline == "¥571.4286")
        #expect(body.progress?.label == "已工作 4 / 7 小时")
        #expect(body.progress?.percent == "57.14%")
    }

    @Test("AC-HOME-02 15:00 打开：距离下班 3:00:00，逐秒递减")
    func countdownTicksDown() throws {
        let state = try onboarded()
        let countdowns = try [standardDay(15, 0), standardDay(15, 0, 1), standardDay(17, 59, 59)].map {
            try attendancePanel(state, at: $0).stats.first
        }

        #expect(countdowns == [
            StatItem(title: "距离下班", value: "3:00:00"),
            StatItem(title: "距离下班", value: "2:59:59"),
            StatItem(title: "距离下班", value: "0:00:01"),
        ])
    }

    @Test("AC-HOME-02 不足一秒的剩余时间向上取整，到计划下班前不会提前显示 0:00:00")
    func countdownRoundsUpPartialSecond() throws {
        let almostSix = Moment(date: standardDay(17, 59, 59).date.addingTimeInterval(0.5), timeZone: shanghai)

        #expect(try attendancePanel(try onboarded(), at: almostSix).stats.first?.value == "0:00:01")
    }

    @Test("F4 场景级：本月前 9 个应出勤日满勤，15:00 本月累计 ¥9571.4286；上班中小字为今日上限与每秒增量")
    func statsAndCaptionWhileWorking() throws {
        // 2026-02-13 周五是 2 月第 10 个应出勤日。
        let body = try attendancePanel(try onboarded(), at: moment(2026, 2, 13, 15, 0))

        #expect(body.caption == "今日上限 ¥1000 · 每秒 +0.0397")
        #expect(body.stats == [
            StatItem(title: "距离下班", value: "3:00:00"),
            StatItem(title: "本月累计", value: "¥9571.4286"),
        ])
    }

    @Test("AC-HOME-03 12:30 打开：状态标签【午休中】，今日已赚与进度 10 秒内不变")
    func lunchBreakPauses() throws {
        let state = try onboarded()
        let at1230 = try #require(snapshot(of: state, at: standardDay(12, 30)).panel)
        let at1230and10 = try #require(snapshot(of: state, at: standardDay(12, 30, 10)).panel)
        let body = try attendancePanel(state, at: standardDay(12, 30))
        let later = try attendancePanel(state, at: standardDay(12, 30, 10))

        #expect(at1230.statusLabel == "午休中")
        #expect(at1230and10.statusLabel == "午休中")
        #expect(body.headline == "¥285.7143")
        #expect(body.progress?.label == "已工作 2 / 7 小时")
        #expect(body.progress?.percent == "28.57%")
        #expect(later.headline == body.headline)
        #expect(later.progress == body.progress)
    }
}

@Suite("今日概览：安装当月")
struct TodayPanelInstallMonthTests {
    @Test("AC-PRE-01 安装当月第 10 个应出勤日首次打开：本月累计 = 9 × 1000 + 今日已赚")
    func daysBeforeInstallCountAsFullAttendance() throws {
        // 2026-02-13 周五是 2 月第 10 个应出勤日，当天 11:00 才完成引导。
        let installDay = moment(2026, 2, 13, 11, 0)
        let state = try onboarded(at: installDay)
        let body = try attendancePanel(state, at: installDay)

        #expect(body.headline == "¥142.8571")
        #expect(body.stats.last == StatItem(title: "本月累计", value: "¥9142.8571"))
        #expect(snapshot(of: state, at: installDay).today?.monthToDate == Decimal(9000) + Decimal(1000) / 7)
    }
}

@Suite("今日概览：休息日")
struct TodayPanelRestDayTests {
    @Test("AC-HOME-06 周六打开：【今天休息】、本月已上班天数、本月累计、下一个应出勤日")
    func saturday() throws {
        // 2026-02-14 周六；2 月 2 日至 13 日共 10 个应出勤日，均按满勤 1000 结算。
        let panel = try #require(snapshot(of: try onboarded(), at: moment(2026, 2, 14, 11, 0)).panel)

        #expect(panel.statusLabel == "休息日")
        #expect(panel.body == .rest(RestPanel(
            headline: "今天休息",
            stats: [
                StatItem(title: "本月已上班", value: "10 天"),
                StatItem(title: "本月累计", value: "¥10000"),
                StatItem(title: "下一个应出勤日", value: "2月16日 周一"),
            ]
        )))
    }
}

@Suite("今日概览：已下班")
struct TodayPanelOffWorkTests {
    @Test("AC-HOME-05 无白干记录 18:30 打开：主数字为今日结算，显示【准点下班，赢】，统计行为今日结算与本月累计，无倒计时")
    func offWorkOnTime() throws {
        // 2026-02-11 是 2 月第 8 个应出勤日：前 7 天 7000 + 今日结算 1000。
        let state = try onboarded()
        let panel = try #require(snapshot(of: state, at: standardDay(18, 30)).panel)
        let body = try attendancePanel(state, at: standardDay(18, 30))

        #expect(panel.statusLabel == "已下班")
        #expect(body.headline == "¥1000.0000")
        #expect(body.caption == "准点下班，赢")
        #expect(body.progress == nil)
        #expect(body.stats == [
            StatItem(title: "今日结算", value: "¥1000"),
            StatItem(title: "本月累计", value: "¥8000"),
        ])
    }
}

@Suite("今日概览：数字格式 (D9)")
struct TodayPanelFormatTests {
    @Test("AC-HOME-12 主数字 4 位小数；统计行整数不带小数点 (¥1000)")
    func integerHasNoDecimalPoint() throws {
        let body = try attendancePanel(try onboarded(), at: standardDay(15, 0))

        #expect(body.headline == "¥571.4286")
        #expect(body.caption == "今日上限 ¥1000 · 每秒 +0.0397")
    }

    @Test("PRD 4.7.1 #5 日薪 952.380952…：主数字补足 4 位 ¥952.3810，其他位置四舍五入后截掉末尾 0 为 ¥952.381")
    func trailingZerosAreTrimmed() throws {
        // 2026 年 5 月只按双休有 21 个应出勤日，日薪 = 20000 ÷ 21。5 月 6 日周三是第 4 个应出勤日。
        let state = try onboarded()
        let working = try attendancePanel(state, at: moment(2026, 5, 6, 15, 0))
        let offWork = try attendancePanel(state, at: moment(2026, 5, 6, 18, 30))

        #expect(working.caption == "今日上限 ¥952.381 · 每秒 +0.0378")
        #expect(offWork.headline == "¥952.3810")
        #expect(offWork.stats == [
            StatItem(title: "今日结算", value: "¥952.381"),
            // 4 × 20000 ÷ 21 = 3809.5238…
            StatItem(title: "本月累计", value: "¥3809.5238"),
        ])
    }

    @Test(
        "PRD 4.3.4 工作进度百分比四舍五入到 2 位并截掉末尾 0；已工作小时数保留 1 位小数、向下取",
        arguments: [
            (8, 30, 0, "已工作 0 / 8 小时", "0%"),
            (10, 0, 0, "已工作 1 / 8 小时", "12.5%"),
            (10, 20, 0, "已工作 1.3 / 8 小时", "16.67%"),
            (17, 57, 0, "已工作 7.9 / 8 小时", "99.38%"),
            (14, 0, 0, "已工作 4 / 8 小时", "50%"),
        ]
    )
    func percentAndHours(hour: Int, minute: Int, second: Int, label: String, percent: String) throws {
        // 默认作息 09:00 至 18:00，午休 12:00 至 13:00，应有有效工时 8 小时。
        let body = try attendancePanel(try onboarded(schedule: .default), at: standardDay(hour, minute, second))

        #expect(body.progress?.label == label)
        #expect(body.progress?.percent == percent)
    }
}

@Suite("今日概览：顶部与进度条")
struct TodayPanelLayoutTests {
    @Test("F4 顶部显示当前日期与时间")
    func header() throws {
        let panel = try #require(snapshot(of: try onboarded(), at: standardDay(15, 7, 30)).panel)

        #expect(panel.dateText == "2月11日 周三")
        #expect(panel.timeText == "15:07")
    }

    @Test("F4 进度条午休显示为间隔：上午、下午各一段，按有效工时占比分宽度")
    func progressBarSplitsAtLunch() throws {
        // 默认作息：上午 3 小时、下午 5 小时；14:00 时上午走满，下午走了 1 / 5。
        let body = try attendancePanel(try onboarded(schedule: .default), at: standardDay(14, 0))

        #expect(body.progress?.segments == [
            ProgressSegment(share: 0.375, filled: 1),
            ProgressSegment(share: 0.625, filled: 0.2),
        ])
    }

    @Test("PRD 4.2.3 #4 关闭午休：进度条只有一段")
    func progressBarWithoutLunch() throws {
        let schedule = WorkSchedule(start: TimeOfDay(hour: 10, minute: 0), end: TimeOfDay(hour: 18, minute: 0), lunch: nil)
        let body = try attendancePanel(try onboarded(schedule: schedule), at: standardDay(12, 0))

        #expect(body.progress?.segments == [ProgressSegment(share: 1, filled: 0.25)])
    }

    @Test("PRD 4.3.5 #3 午休紧贴计划上班或下班时：进度条不出现零长度的段", arguments: [(10, 11), (17, 18)])
    func lunchTouchingStartOrEndHasNoEmptySegment(lunch: (Int, Int)) throws {
        // 午休落在上下班之内即合法，可以从计划上班开始或到计划下班结束。
        let schedule = WorkSchedule(
            start: TimeOfDay(hour: 10, minute: 0),
            end: TimeOfDay(hour: 18, minute: 0),
            lunch: LunchBreak(start: TimeOfDay(hour: lunch.0, minute: 0), end: TimeOfDay(hour: lunch.1, minute: 0))
        )
        let body = try attendancePanel(try onboarded(schedule: schedule), at: standardDay(14, 30))

        #expect(body.progress?.segments.count == 1)
        #expect(body.progress?.segments.allSatisfy { $0.share == 1 && $0.filled.isFinite } == true)
    }
}
