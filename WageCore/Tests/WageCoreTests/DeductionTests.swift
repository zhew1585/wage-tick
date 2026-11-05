import Foundation
import Testing
import WageCore

/// 在 `now` 时刻按金额给今天记一笔扣钱。
func recordingDeduction(
    _ amount: DeductionAmount,
    reason: DeductionReason? = nil,
    note: String = "",
    on state: AppState,
    at now: Moment
) throws -> AppState {
    let input = DeductionInput(amount: amount, reason: reason, note: note)
    return try apply(.addDeduction(input), to: state, at: now).state
}

@Suite("今天扣钱了：记账")
struct DeductionRecordingTests {
    @Test("AC-FINE-01 15:00 记 50 元：今日已赚从 571.4286 变为 542.8571，继续增长")
    func fixedAmountDropsEarnedThenKeepsRolling() throws {
        let state = try onboarded()
        let before = snapshot(of: state, at: standardDay(15, 0))
        let fined = try recordingDeduction(.fixed(50), on: state, at: standardDay(15, 0))
        let after = snapshot(of: fined, at: standardDay(15, 0))
        let later = snapshot(of: fined, at: standardDay(15, 0, 10))

        #expect(before.menuBar.text == "571.4286")
        #expect(after.menuBar.text == "542.8571")
        #expect(try #require(after.today?.earnings).cap == 950)
        #expect(try #require(later.today?.earnings).earned > (try #require(after.today?.earnings).earned))
    }
}

@Suite("今天扣钱了：今日上限与本月累计")
struct DeductionSettlementTests {
    @Test("AC-FINE-02 记日薪 10%：扣 100 元，今日上限 900")
    func percentOfDailyWage() throws {
        let fined = try recordingDeduction(.percentOfDailyWage(10), on: try onboarded(), at: standardDay(15, 0))
        let earnings = try #require(snapshot(of: fined, at: standardDay(15, 0)).today?.earnings)

        #expect(earnings.deductionTotal == 100)
        #expect(earnings.cap == 900)
    }

    @Test("PRD 4.4.1 #2 按日薪百分比：金额 = 当月日薪 × 比例，日薪 952.381 时扣 10% 为 95.2381")
    func percentFollowsMonthDailyWage() throws {
        // 2026 年 5 月只按双休有 21 个应出勤日，日薪 = 20000 ÷ 21。
        let fined = try recordingDeduction(.percentOfDailyWage(10), on: try onboarded(), at: moment(2026, 5, 6, 15, 0))
        let earnings = try #require(snapshot(of: fined, at: moment(2026, 5, 6, 15, 0)).today?.earnings)

        #expect(earnings.deductionTotal == Decimal(2000) / 21)
        #expect(rounded4(earnings.deductionTotal) == Decimal(string: "95.2381")!)
    }

    @Test("AC-FINE-04 同一天记 2 笔：当日扣款为两笔之和")
    func twoDeductionsAddUp() throws {
        var state = try onboarded()
        state = try recordingDeduction(.fixed(50), reason: .late, on: state, at: standardDay(10, 30))
        state = try recordingDeduction(.percentOfDailyWage(10), on: state, at: standardDay(15, 0))
        let earnings = try #require(snapshot(of: state, at: standardDay(15, 0)).today?.earnings)

        #expect(earnings.deductionTotal == 150)
        #expect(earnings.cap == 850)
    }

    @Test("AC-FINE-05 记 1200 元：今日上限 0，今日已赚停在 0，菜单栏 0.0000【D1】")
    func overDeductionFloorsAtZero() throws {
        let fined = try recordingDeduction(.fixed(1200), on: try onboarded(), at: standardDay(15, 0))
        let snap = snapshot(of: fined, at: standardDay(15, 0))
        let earnings = try #require(snap.today?.earnings)

        #expect(earnings.cap == 0)
        #expect(earnings.earned == 0)
        #expect(earnings.perSecond == 0)
        #expect(snap.menuBar.text == "0.0000")
        #expect(snapshot(of: fined, at: standardDay(18, 30)).menuBar.text == "0.0000")
    }

    @Test("PRD 4.3.4 本月累计算例：前 9 个应出勤日满勤，今天 15:00 有扣钱 50 元，9 × 1000 + 542.8571 = 9542.8571")
    func monthToDateWithTodayDeduction() throws {
        // 2026-02-13 周五是 2 月第 10 个应出勤日。
        let now = moment(2026, 2, 13, 15, 0)
        let fined = try recordingDeduction(.fixed(50), on: try onboarded(), at: now)
        let today = try #require(snapshot(of: fined, at: now).today)

        #expect(rounded4(today.monthToDate) == Decimal(string: "9542.8571")!)
    }

    @Test("PRD 4.3.4 本月累计按已过各日结算求和：周三记的 50 元扣钱，周五、周六仍从本月累计里扣掉")
    func pastDayDeductionStaysInMonthToDate() throws {
        // 2026-02-11 周三 (第 8 个应出勤日) 记 50 元，02-13 周五 15:00 看：8 × 1000 + 950 + 571.4286。
        let fined = try recordingDeduction(.fixed(50), on: try onboarded(), at: standardDay(15, 0))
        let friday = try #require(snapshot(of: fined, at: moment(2026, 2, 13, 15, 0)).today)
        let saturday = try #require(snapshot(of: fined, at: moment(2026, 2, 14, 11, 0)).today)

        #expect(rounded4(friday.monthToDate) == Decimal(string: "9521.4286")!)
        #expect(saturday.monthToDate == 9950)
    }

    @Test("PRD 4.3.4 过去一天扣款超过日薪：该天结算为 0，不会倒扣本月累计【D1】")
    func pastOverDeductionSettlesAtZero() throws {
        let fined = try recordingDeduction(.fixed(1200), on: try onboarded(), at: standardDay(15, 0))
        let saturday = try #require(snapshot(of: fined, at: moment(2026, 2, 14, 11, 0)).today)

        // 2 月 2 日至 13 日共 10 个应出勤日，其中 11 日结算为 0。
        #expect(saturday.monthToDate == 9000)
    }

    @Test("PRD 4.3.4 扣钱只影响所在月：下个月本月累计不受影响")
    func deductionDoesNotLeakIntoNextMonth() throws {
        let fined = try recordingDeduction(.fixed(50), on: try onboarded(), at: standardDay(15, 0))
        // 2026-03-02 周一是 3 月第 1 个应出勤日，18:30 已下班。
        let today = try #require(snapshot(of: fined, at: moment(2026, 3, 2, 18, 30)).today)

        #expect(rounded4(today.monthToDate) == Decimal(string: "909.0909")!)
    }
}

@Suite("今天扣钱了：校验")
struct DeductionValidationTests {
    @Test(
        "AC-FINE-06 金额填 0 或负数：提示【扣钱金额得大于 0】",
        arguments: [DeductionAmount.fixed(0), .fixed(-5), .percentOfDailyWage(0)]
    )
    func amountMustBePositive(amount: DeductionAmount) throws {
        let input = DeductionInput(amount: amount, reason: nil, note: "")

        #expect(throws: CommandError.deductionNotPositive) {
            try apply(.addDeduction(input), to: try onboarded(), at: standardDay(15, 0))
        }
        #expect(CommandError.deductionNotPositive.message == "扣钱金额得大于 0")
    }

    @Test("PRD 4.4.1 备注最多 50 字：50 字可以保存，51 字拦下")
    func noteLimit() throws {
        let state = try onboarded()
        let fifty = DeductionInput(amount: .fixed(50), reason: .other, note: String(repeating: "扣", count: 50))
        let fiftyOne = DeductionInput(amount: .fixed(50), reason: .other, note: String(repeating: "扣", count: 51))

        #expect(throws: Never.self) { try apply(.addDeduction(fifty), to: state, at: standardDay(15, 0)) }
        #expect(throws: CommandError.deductionNoteTooLong) {
            try apply(.addDeduction(fiftyOne), to: state, at: standardDay(15, 0))
        }
    }

    @Test("PRD 4.3.5 #8 休息日不能记扣钱：提示【今天本来就不上班】")
    func restDayRejected() throws {
        let input = DeductionInput(amount: .fixed(50), reason: nil, note: "")

        #expect(throws: CommandError.notAttendanceDay) {
            try apply(.addDeduction(input), to: try onboarded(), at: moment(2026, 2, 14, 11, 0))
        }
        #expect(CommandError.notAttendanceDay.message == "今天本来就不上班")
    }

    @Test("未完成引导不能记扣钱")
    func requiresOnboarding() throws {
        let input = DeductionInput(amount: .fixed(50), reason: nil, note: "")

        #expect(throws: CommandError.notOnboarded) {
            try apply(.addDeduction(input), to: AppState(), at: standardDay(15, 0))
        }
    }
}

@Suite("今天扣钱了：编辑与删除")
struct DeductionEditingTests {
    /// 今天 10:30 记了迟到 50 元、15:00 记了日薪 10%，返回状态与两笔的标识。
    private func twoDeductions() throws -> (state: AppState, ids: [Int]) {
        var state = try onboarded()
        state = try recordingDeduction(.fixed(50), reason: .late, on: state, at: standardDay(10, 30))
        state = try recordingDeduction(.percentOfDailyWage(10), on: state, at: standardDay(15, 0))
        let ids = try attendancePanel(state, at: standardDay(15, 0)).deductions.map(\.id)
        return (state, ids)
    }

    @Test("PRD 4.4.1 #1 编辑一笔：当日扣款按新数值重算，另一笔不变")
    func editOne() throws {
        let (state, ids) = try twoDeductions()
        let input = DeductionInput(amount: .fixed(80), reason: .late, note: "地铁故障")
        let edited = try apply(.editDeduction(id: ids[0], input), to: state, at: standardDay(15, 5)).state
        let body = try attendancePanel(edited, at: standardDay(15, 5))

        #expect(try #require(snapshot(of: edited, at: standardDay(15, 5)).today?.earnings).deductionTotal == 180)
        #expect(body.deductions.map(\.id) == ids)
        #expect(body.deductions.first?.input == input)
    }

    @Test("PRD 4.4.1 #1 删除一笔：当日扣款只剩另一笔；全部删完今日上限回到日薪")
    func deleteOneThenAll() throws {
        let (state, ids) = try twoDeductions()
        let one = try apply(.deleteDeduction(id: ids[0]), to: state, at: standardDay(15, 5)).state
        let none = try apply(.deleteDeduction(id: ids[1]), to: one, at: standardDay(15, 5)).state

        #expect(try #require(snapshot(of: one, at: standardDay(15, 5)).today?.earnings).deductionTotal == 100)
        #expect(try #require(snapshot(of: none, at: standardDay(15, 5)).today?.earnings).cap == 1000)
        #expect(none.dayRecords.isEmpty)
    }

    @Test("编辑或删除不存在的扣钱：提示【这笔扣钱已经不在了】")
    func unknownDeduction() throws {
        let (state, ids) = try twoDeductions()
        let gone = try apply(.deleteDeduction(id: ids[0]), to: state, at: standardDay(15, 5)).state
        let input = DeductionInput(amount: .fixed(80), reason: nil, note: "")

        #expect(throws: CommandError.deductionNotFound) {
            try apply(.deleteDeduction(id: ids[0]), to: gone, at: standardDay(15, 5))
        }
        #expect(throws: CommandError.deductionNotFound) {
            try apply(.editDeduction(id: ids[0], input), to: gone, at: standardDay(15, 5))
        }
    }

    @Test("本票只能改删今天的扣钱：第二天再改删昨天的一笔视为找不到，补记过去留给历史编辑")
    func onlyToday() throws {
        let (state, ids) = try twoDeductions()
        let input = DeductionInput(amount: .fixed(80), reason: nil, note: "")
        let tomorrow = moment(2026, 2, 12, 10, 0)

        #expect(throws: CommandError.deductionNotFound) {
            try apply(.editDeduction(id: ids[0], input), to: state, at: tomorrow)
        }
        #expect(throws: CommandError.deductionNotFound) {
            try apply(.deleteDeduction(id: ids[0]), to: state, at: tomorrow)
        }
    }

    @Test("编辑同样要校验：金额改成 0 被拦下，原记录不变")
    func editValidates() throws {
        let (state, ids) = try twoDeductions()
        let input = DeductionInput(amount: .fixed(0), reason: nil, note: "")

        #expect(throws: CommandError.deductionNotPositive) {
            try apply(.editDeduction(id: ids[0], input), to: state, at: standardDay(15, 5))
        }
    }
}

@Suite("今天扣钱了：保存与读回")
struct DeductionPersistenceTests {
    @Test("PRD 4.3.5 #14 扣钱记录存成 JSON 再读回，快照不变")
    func survivesPersistence() throws {
        var state = try onboarded()
        state = try recordingDeduction(.fixed(Decimal(string: "12.34")!), reason: .late, note: "地铁", on: state, at: standardDay(10, 30))
        state = try recordingDeduction(.percentOfDailyWage(Decimal(string: "33.3")!), on: state, at: standardDay(15, 0))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(snapshot(of: restored, at: standardDay(15, 0)) == snapshot(of: state, at: standardDay(15, 0)))
    }

    @Test("读回时拒绝数值不大于 0 的扣钱记录")
    func rejectsNonPositiveOnDecode() throws {
        let json = """
        {"dayRecords":[{"date":{"year":2026,"month":2,"day":11},
          "deductions":[{"id":1,"note":"","amount":{"method":"fixed","value":"0"}}]}]}
        """

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AppState.self, from: Data(json.utf8)) }
    }
}

@Suite("读回状态时拒绝日记录冲突")
struct DayRecordDecodingTests {
    private func decode(_ records: String) throws -> AppState {
        try JSONDecoder().decode(AppState.self, from: Data("{\"dayRecords\":[\(records)]}".utf8))
    }

    private static let feb11 = #"{"year":2026,"month":2,"day":11}"#
    private static let feb12 = #"{"year":2026,"month":2,"day":12}"#

    private static func record(_ date: String, ids: [Int]) -> String {
        let items = ids.map { #"{"id":\#($0),"note":"","amount":{"method":"fixed","value":"50"}}"# }
        return #"{"date":\#(date),"deductions":[\#(items.joined(separator: ","))]}"#
    }

    @Test("同一天有两条日记录：拒绝")
    func duplicateDate() {
        #expect(throws: DecodingError.self) {
            try decode([Self.record(Self.feb11, ids: [1]), Self.record(Self.feb11, ids: [2])].joined(separator: ","))
        }
    }

    @Test("扣钱记录标识重复：拒绝，免得编辑、删除改错一笔")
    func duplicateDeductionID() {
        #expect(throws: DecodingError.self) {
            try decode([Self.record(Self.feb11, ids: [1]), Self.record(Self.feb12, ids: [1])].joined(separator: ","))
        }
    }

    @Test("合法的日记录可以读回")
    func validRecords() throws {
        let state = try decode([Self.record(Self.feb12, ids: [2]), Self.record(Self.feb11, ids: [1])].joined(separator: ","))

        #expect(state.dayRecords.map(\.date.day) == [11, 12])
    }
}
