import Foundation
import Testing
import WageCore

// 下班通知 (PRD 4.6.3、F13)：外壳每次刷新先发 `advance` 再取快照，
// 跨过当日计划下班时 `advance` 返回一次下班事件，事件里带好通知文案。

/// 模拟外壳的一串刷新：依次在每个此刻发 `advance`，返回最终状态和沿途产生的全部事件。
private func refreshes(
    _ state: AppState,
    at moments: [Moment],
    holidays: HolidayTable = .empty
) throws -> (state: AppState, events: [DomainEvent]) {
    var current = state
    var events: [DomainEvent] = []
    for now in moments {
        let result = try apply(.advance, to: current, at: now, holidays: holidays)
        current = result.state
        events += result.events
    }
    return (current, events)
}

private func applied(_ command: Command, to state: AppState, at now: Moment = standardDay(9, 0)) throws -> AppState {
    try apply(command, to: state, at: now).state
}

private let standardNotice = DomainEvent.offWork(message: "今日 1000 元已到账，可以走了")

@Suite("下班通知：什么时候发")
struct OffWorkNoticeTriggerTests {
    @Test("AC-NTF-01 标准算例无扣钱，到 18:00 收到【今日 1000 元已到账，可以走了】")
    func standardCase() throws {
        let beforeEnd = try refreshes(try onboarded(), at: [standardDay(9, 30), standardDay(17, 59, 59)])
        #expect(beforeEnd.events.isEmpty)

        let atEnd = try apply(.advance, to: beforeEnd.state, at: standardDay(18, 0))
        #expect(atEnd.events == [standardNotice])
    }

    @Test("AC-NTF-02 周六不发下班通知")
    func saturday() throws {
        // 2026-02-14 是周六。
        let day = { (hour: Int) in moment(2026, 2, 14, hour, 0) }
        let result = try refreshes(try onboarded(), at: [day(9), day(17), day(18), day(23)])

        #expect(result.events.isEmpty)
    }

    @Test("PRD 4.2.2 法定节假日不发，调休上班日照常发")
    func followsHolidayTable() throws {
        let state = try onboarded()

        // 2026-02-16 (周一) 设为法定节假日。
        let holidays = HolidayTable(days: [LocalDate(year: 2026, month: 2, day: 16): .holiday])
        let holiday = try refreshes(state, at: [moment(2026, 2, 16, 17, 0), moment(2026, 2, 16, 18, 0)], holidays: holidays)
        #expect(holiday.events.isEmpty)

        // 2026-02-14 (周六) 设为调休上班日，2 月变成 21 个应出勤日：20000 ÷ 21 = 952.380952…，
        // 通知里四舍五入到 4 位后截掉末尾 0。
        let makeupDays = HolidayTable(days: [LocalDate(year: 2026, month: 2, day: 14): .makeupDay])
        let makeup = try refreshes(state, at: [moment(2026, 2, 14, 17, 0), moment(2026, 2, 14, 18, 0)], holidays: makeupDays)
        #expect(makeup.events == [.offWork(message: "今日 952.381 元已到账，可以走了")])
    }

    @Test("PRD 4.7.1 第 5 条 通知里的金额截掉末尾 0，不补 4 位小数")
    func trimmedAmount() throws {
        // 20001 ÷ 20 = 1000.05。
        let result = try refreshes(try onboarded(salary: 20001), at: [standardDay(17, 0), standardDay(18, 0)])

        #expect(result.events == [.offWork(message: "今日 1000.05 元已到账，可以走了")])
    }

    @Test("AC-BOSS-03 老板路过模式下通知为【今天的砖搬完了，可以走了】，不含金额")
    func bossModeHidesAmount() throws {
        let state = try applied(.toggleBossMode, to: try onboarded())
        let result = try refreshes(state, at: [standardDay(17, 0), standardDay(18, 0)])

        #expect(result.events == [.offWork(message: "今天的砖搬完了，可以走了")])
    }

    @Test("PRD 4.3.5 #14 下班前睡眠、下班后醒来：醒来那次刷新补发一次")
    func crossedWhileAsleep() throws {
        let result = try refreshes(try onboarded(), at: [standardDay(17, 50), standardDay(21, 0), standardDay(21, 0, 1)])

        #expect(result.events == [standardNotice])
    }

    @Test("下班后才第一次看到今天 (如晚上才开机、晚上才完成引导)：没有跨过下班，不发")
    func firstSeenAfterEnd() throws {
        let lateOnboarding = try refreshes(try onboarded(at: standardDay(19, 0)), at: [standardDay(19, 0), standardDay(20, 0)])
        #expect(lateOnboarding.events.isEmpty)

        // 昨天下班前睡眠，今天下班后才醒：昨天的下班不补发，今天也没跨过。
        let yesterday = moment(2026, 2, 10, 17, 0)
        let overnight = try refreshes(try onboarded(at: yesterday), at: [yesterday, standardDay(19, 0)])
        #expect(overnight.events.isEmpty)
    }

    @Test("第二天照常再发一次")
    func nextDayAgain() throws {
        let result = try refreshes(try onboarded(), at: [
            standardDay(17, 0), standardDay(18, 0),
            moment(2026, 2, 12, 9, 0), moment(2026, 2, 12, 18, 0),
        ])

        #expect(result.events == [standardNotice, standardNotice])
    }

    @Test("未完成引导时推进到此刻什么都不变")
    func beforeOnboarding() throws {
        let result = try apply(.advance, to: AppState(), at: standardDay(18, 0))

        #expect(result.state == AppState())
        #expect(result.events.isEmpty)
    }
}

@Suite("下班通知：同一天不重复")
struct OffWorkNoticeOnceTests {
    @Test("下班后继续刷新不再发")
    func keepsRefreshing() throws {
        let result = try refreshes(try onboarded(), at: [
            standardDay(17, 0), standardDay(18, 0), standardDay(18, 0, 1), standardDay(23, 59),
        ])

        #expect(result.events == [standardNotice])
    }

    @Test("PRD 4.3.5 #14 发过之后重启：状态存成 JSON 再读回，不再发")
    func survivesRestart() throws {
        let notified = try refreshes(try onboarded(), at: [standardDay(17, 0), standardDay(18, 0)])
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(notified.state))

        #expect(restored == notified.state)
        #expect(try refreshes(restored, at: [standardDay(18, 30)]).events.isEmpty)
    }

    @Test("下班前重启：读回的状态记得今天还没下班，到点照常发")
    func restartBeforeEnd() throws {
        let waiting = try refreshes(try onboarded(), at: [standardDay(17, 0)])
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(waiting.state))

        #expect(try refreshes(restored, at: [standardDay(18, 0)]).events == [standardNotice])
    }

    @Test("发过之后把下班改晚：今天又回到上班中，到新的下班时刻也不再发")
    func laterEndAfterNotice() throws {
        let notified = try refreshes(try onboarded(), at: [standardDay(17, 0), standardDay(18, 0)])
        let later = WorkSchedule(start: standardSchedule.start, end: TimeOfDay(hour: 20, minute: 0), lunch: standardSchedule.lunch)
        let changed = try applied(.changeSchedule(later), to: notified.state, at: standardDay(18, 30))

        #expect(try refreshes(changed, at: [standardDay(18, 31), standardDay(20, 0)]).events.isEmpty)
    }

    @Test("AC-SET-02 下班前把下班改早到已过的时刻：立即算到达下班，发一次")
    func earlierEndBeforeNotice() throws {
        let waiting = try refreshes(try onboarded(), at: [standardDay(15, 0)])
        let earlier = WorkSchedule(start: standardSchedule.start, end: TimeOfDay(hour: 14, minute: 0), lunch: standardSchedule.lunch)
        let changed = try applied(.changeSchedule(earlier), to: waiting.state, at: standardDay(15, 0))

        // 当日计划 10:00 至 14:00 扣午休 3 小时，今日上限仍是日薪 1000。
        #expect(try refreshes(changed, at: [standardDay(15, 0), standardDay(15, 1)]).events == [standardNotice])
    }
}

@Suite("下班通知开关")
struct OffWorkNoticeSettingTests {
    @Test("PRD 4.7.2 下班通知默认开，引导前也能改")
    func defaultOnAndChangeable() throws {
        #expect(snapshot(of: try onboarded(), at: standardDay(9, 0)).settings.offWorkNotification)

        let off = try applied(.setOffWorkNotification(false), to: AppState())
        #expect(snapshot(of: off, at: standardDay(9, 0)).settings.offWorkNotification == false)
    }

    @Test("AC-NTF-05 设置关闭下班通知后不再发送")
    func disabled() throws {
        let state = try applied(.setOffWorkNotification(false), to: try onboarded())
        let result = try refreshes(state, at: [standardDay(17, 0), standardDay(18, 0), standardDay(18, 1)])

        #expect(result.events.isEmpty)
    }

    @Test("关着通知跨过下班，之后再打开：今天的下班已经过去，不补发；第二天照常发")
    func reenabledAfterEnd() throws {
        let off = try applied(.setOffWorkNotification(false), to: try onboarded())
        let passed = try refreshes(off, at: [standardDay(17, 0), standardDay(18, 0)])
        let on = try applied(.setOffWorkNotification(true), to: passed.state, at: standardDay(18, 30))

        let result = try refreshes(on, at: [standardDay(18, 31), moment(2026, 2, 12, 17, 0), moment(2026, 2, 12, 18, 0)])
        #expect(result.events == [standardNotice])
    }

    @Test("开关随状态存盘；旧文件没有这个字段时按默认开读回")
    func persisted() throws {
        let off = try applied(.setOffWorkNotification(false), to: try onboarded())
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(off))
        #expect(restored.settings.offWorkNotification == false)

        let legacy = try JSONDecoder().decode(InterfaceSettings.self, from: Data(#"{"bossMode":true}"#.utf8))
        #expect(legacy.offWorkNotification)
    }

    @Test("AC-SET-05 系统拒绝通知权限时设置页的提示文案")
    func permissionDeniedNotice() {
        #expect(NotificationCopy.permissionDenied == "通知被关了，去系统设置里打开")
    }
}
