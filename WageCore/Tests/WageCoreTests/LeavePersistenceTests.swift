import Foundation
import Testing
import WageCore

// 请假读回状态 (PRD 4.3.5 #14)：新格式存时段，V1.8 之前存的「全天 / 上午 / 下午」按那天的作息换算成时段。

/// 把状态编码成 JSON 对象，交给 `edit` 改，再读回。
private func roundTrip(_ state: AppState, editing edit: (inout [String: Any]) -> Void) throws -> AppState {
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    edit(&json)
    return try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: json))
}

/// 把各条日记录里的请假换成旧格式的时段名 (按日记录先后)。
private func legacyLeaves(_ periods: [String]) -> (inout [String: Any]) -> Void {
    { json in
        var records = json["dayRecords"] as! [[String: Any]]
        for (index, period) in periods.enumerated() {
            let percent = (records[index]["leave"] as! [String: Any])["deductionPercent"]!
            records[index]["leave"] = ["period": period, "deductionPercent": percent]
        }
        json["dayRecords"] = records
    }
}

@Suite("请假：读回状态")
struct LeavePersistenceTests {
    @Test("PRD 4.3.5 #14 请假存成 JSON 再读回，快照不变")
    func leaveSurvivesPersistence() throws {
        let state = try onLeave(leave("14:00", "16:00", Decimal(string: "33.3")!))
        let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))

        #expect(restored == state)
        #expect(snapshot(of: restored, at: standardDay(15, 0)) == snapshot(of: state, at: standardDay(15, 0)))
    }

    @Test("文件里的扣薪比例超出 0% 至 100% 时拒绝读入")
    func invalidPercentIsRejected() throws {
        let json = String(decoding: try JSONEncoder().encode(try onLeave(secondHalfLeave(50))), as: UTF8.self)
        let corrupted = json.replacingOccurrences(of: "\"deductionPercent\":\"50\"", with: "\"deductionPercent\":\"120\"")
        #expect(corrupted != json)

        #expect(throws: DecodingError.self) { try JSONDecoder().decode(AppState.self, from: Data(corrupted.utf8)) }
    }

    @Test("文件里的请假结束不晚于开始时拒绝读入")
    func invalidRangeIsRejected() throws {
        let state = try onLeave(leave("14:00", "16:00", 10))

        #expect(throws: DecodingError.self) {
            try roundTrip(state) { json in
                var records = json["dayRecords"] as! [[String: Any]]
                var leave = records[0]["leave"] as! [String: Any]
                leave["end"] = ["hour": 13, "minute": 0]
                records[0]["leave"] = leave
                json["dayRecords"] = records
            }
        }
    }
}

@Suite("请假：旧格式换算")
struct LegacyLeaveTests {
    @Test("全天、上午、下午按当天作息换算成全天、前半天、后半天，比例原样保留", arguments: [
        ("fullDay", "10:00", "18:00"),
        ("morning", "10:00", "12:00"),
        ("afternoon", "13:00", "18:00"),
    ])
    func convertsWithSchedule(period: String, start: String, end: String) throws {
        let restored = try roundTrip(try onLeave(fullDayLeave(50)), editing: legacyLeaves([period]))

        #expect(snapshot(of: restored, at: standardDay(9, 0)).today?.leave == leave(start, end, 50))
        // 换算后再存就是新格式，读回不变。
        #expect(try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(restored)) == restored)
    }

    @Test("旧的下午假换算后与原来的推导一致：11:00 今日已赚 250，12:00 已下班")
    func afternoonBehavesAsBefore() throws {
        let restored = try roundTrip(try onLeave(fullDayLeave(50)), editing: legacyLeaves(["afternoon"]))

        #expect(snapshot(of: restored, at: standardDay(11, 0)).menuBar.text == "250.0000")
        #expect(snapshot(of: restored, at: standardDay(12, 0)).today?.status == .offWork)
    }

    @Test("按那天生效的作息换算：改作息之前的日子用旧作息，之后的用新作息")
    func usesScheduleInEffectThatDay() throws {
        let installed = try onboarded(at: moment(2026, 2, 2, 9, 0))
        let past = try sending(.editDay(LocalDate(year: 2026, month: 2, day: 4), .setLeave(fullDayLeave(50))), to: installed)
        let later = WorkSchedule(start: clock("09:00"), end: clock("17:00"), lunch: LunchBreak(start: clock("11:30"), end: clock("12:30")))
        let changed = try sending(.changeSchedule(later), to: past)
        let both = try sending(.setLeave(leave("09:00", "17:00", 50)), to: changed)
        let restored = try roundTrip(both, editing: legacyLeaves(["morning", "morning"]))

        #expect(restored.dayRecords.map(\.leave) == [leave("10:00", "12:00", 50), leave("09:00", "11:30", 50)])
    }

    @Test("关闭饭点时以中点为分界：上午假为 10:00 至 14:00")
    func withoutLunch() throws {
        let noLunch = WorkSchedule(start: clock("10:00"), end: clock("18:00"), lunch: nil)
        let restored = try roundTrip(try onLeave(fullDayLeave(50), schedule: noLunch), editing: legacyLeaves(["morning"]))

        #expect(restored.dayRecords.first?.leave == leave("10:00", "14:00", 50))
    }

    @Test("饭点紧贴计划上班时的旧上午假 (没有时长)：换成饭点那段，当日计划与原来一样从饭点结束开始")
    func emptyHalfFallsBackToLunch() throws {
        let schedule = WorkSchedule(
            start: clock("10:00"), end: clock("18:00"), lunch: LunchBreak(start: clock("10:00"), end: clock("11:00"))
        )
        let restored = try roundTrip(try onLeave(fullDayLeave(50), schedule: schedule), editing: legacyLeaves(["morning"]))

        #expect(restored.dayRecords.first?.leave == leave("10:00", "11:00", 50))
        #expect(snapshot(of: restored, at: standardDay(10, 30)).today?.status == .notStarted)
        #expect(snapshot(of: restored, at: standardDay(11, 0)).today?.status == .working)
    }

    @Test("没有引导配置时旧格式的请假换算不了，拒绝读入")
    func legacyWithoutProfileIsRejected() throws {
        let state = try onLeave(fullDayLeave(50))

        #expect(throws: DecodingError.self) {
            try roundTrip(state) { json in
                legacyLeaves(["fullDay"])(&json)
                json["profile"] = nil
            }
        }
    }
}
