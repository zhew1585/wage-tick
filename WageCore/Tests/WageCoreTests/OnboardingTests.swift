import Foundation
import Testing
import WageCore

@Suite("首次引导")
struct OnboardingTests {
    @Test("AC-ONB-04 未完成引导：菜单栏只有小牛，无数字")
    func notOnboardedShowsOnlyCow() {
        let snap = snapshot(of: AppState(), at: standardDay(11, 0))

        #expect(snap.menuBar.text == nil)
        #expect(snap.today == nil)
    }
}

@Suite("首次引导：校验与完成")
struct OnboardingValidationTests {
    private func complete(salary: Decimal = 20000, schedule: WorkSchedule = standardSchedule) -> CommandError? {
        let input = OnboardingInput(salary: salary, schedule: schedule, launchAtLogin: true)
        do {
            _ = try apply(.completeOnboarding(input), to: AppState(), at: standardDay(9, 0))
            return nil
        } catch {
            return error
        }
    }

    private func schedule(_ start: Int, _ end: Int, lunch: (Int, Int)? = (12, 13)) -> WorkSchedule {
        WorkSchedule(
            start: TimeOfDay(hour: start, minute: 0),
            end: TimeOfDay(hour: end, minute: 0),
            lunch: lunch.map { LunchBreak(start: TimeOfDay(hour: $0.0, minute: 0), end: TimeOfDay(hour: $0.1, minute: 0)) }
        )
    }

    @Test("AC-ONB-02 / PRD 4.3.5 #1 月薪为 0 或负数：提示「月薪得是个正数」", arguments: [Decimal(0), Decimal(-1)])
    func salaryMustBePositive(salary: Decimal) {
        let error = complete(salary: salary)

        #expect(error == .salaryNotPositive)
        #expect(error?.message == "月薪得是个正数")
    }

    @Test("PRD 4.2.1 月薪最多 2 位小数", arguments: ["20000.123", "0.001"])
    func salaryHasAtMostTwoDecimals(text: String) {
        #expect(complete(salary: Decimal(string: text)!) == .salaryNotPositive)
    }

    @Test("PRD 4.2.1 月薪 2 位小数以内可以保存", arguments: ["20000.12", "0.01", "8000"])
    func salaryWithTwoDecimalsIsAccepted(text: String) {
        #expect(complete(salary: Decimal(string: text)!) == nil)
    }

    @Test("AC-ONB-03 / PRD 4.3.5 #2 下班不晚于上班：提示「下班时间要晚于上班时间」", arguments: [8, 9])
    func endMustBeAfterStart(end: Int) {
        let error = complete(schedule: schedule(9, end, lunch: nil))

        #expect(error == .endNotAfterStart)
        #expect(error?.message == "下班时间要晚于上班时间")
    }

    @Test(
        "PRD 4.3.5 #3 饭点不在上下班之内或结束不晚于开始：提示「饭点要在上下班时间之内」",
        arguments: [(8, 13), (12, 19), (13, 12), (12, 12), (9, 18)]
    )
    func lunchMustBeInsideWorkHours(lunch: (Int, Int)) {
        let error = complete(schedule: schedule(9, 18, lunch: lunch))

        #expect(error == .lunchOutsideWorkHours)
        #expect(error?.message == "饭点要在上下班时间之内")
    }

    @Test("PRD 4.3.5 #1 至 #3 分步校验：外壳单独校验月薪与作息，结果与命令一致")
    func stepValidationMatchesCommand() {
        #expect(Validation.salary(0, basis: .monthly) == .salaryNotPositive)
        #expect(Validation.salary(Decimal(string: "0.01")!, basis: .monthly) == nil)
        #expect(Validation.schedule(schedule(9, 8, lunch: nil)) == .endNotAfterStart)
        #expect(Validation.schedule(schedule(9, 18, lunch: (8, 13))) == .lunchOutsideWorkHours)
        #expect(Validation.schedule(.default) == nil)
    }

    @Test("AC-ONB-01 默认作息：09:00 至 18:00，饭点 12:00 至 13:00，标准工时 8 小时")
    func defaultSchedule() throws {
        let state = try onboarded(schedule: .default)
        let statuses = [(8, 59), (9, 0), (12, 0), (13, 0), (18, 0)].map { hour, minute in
            snapshot(of: state, at: standardDay(hour, minute)).today?.status
        }

        #expect(statuses == [.notStarted, .working, .lunchBreak, .working, .offWork])
        // 09:00 至 15:00 扣饭点共 5 小时，占 8 小时 (9 - 1) 的 62.5%。
        #expect(snapshot(of: state, at: standardDay(15, 0)).menuBar.text == "625.0000")
    }

    @Test("PRD 4.1.1 完成引导后菜单栏出现数字；安装当天按作息计入，不从完成时刻起算")
    func onboardingMidDayCountsWholeSchedule() throws {
        let state = try onboarded(at: standardDay(11, 0))

        #expect(snapshot(of: state, at: standardDay(11, 0)).menuBar == MenuBarDisplay(pose: .grinding, text: "142.8571"))
    }

    @Test("PRD 4.1.1 引导只能完成一次")
    func cannotOnboardTwice() throws {
        let state = try onboarded()
        let input = OnboardingInput(salary: 30000, schedule: .default, launchAtLogin: false)

        #expect(throws: CommandError.alreadyOnboarded) {
            try apply(.completeOnboarding(input), to: state, at: standardDay(10, 0))
        }
    }

    @Test("PRD 4.7.2 开机自启默认开：引导不再询问，不传时按默认值保存")
    func launchAtLoginDefaultsOn() throws {
        let input = OnboardingInput(salary: 20000, schedule: .default)
        let state = try apply(.completeOnboarding(input), to: AppState(), at: standardDay(9, 0)).state

        #expect(input.launchAtLogin == true)
        #expect(state.profile?.launchAtLogin == true)
    }

    @Test("开机自启：命令里显式传入的值原样保存在状态里")
    func launchAtLoginIsStored() throws {
        let input = OnboardingInput(salary: 20000, schedule: .default, launchAtLogin: false)
        let state = try apply(.completeOnboarding(input), to: AppState(), at: standardDay(9, 0)).state

        #expect(state.profile?.launchAtLogin == false)
    }
}
