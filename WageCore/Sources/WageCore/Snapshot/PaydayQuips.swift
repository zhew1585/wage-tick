import Foundation

/// 悬浮小牛气泡里的台词 (issue #21)：每个心情档位 3 至 5 句，第一句是 issue 表里的示例。
/// 每天按日期固定挑一句：同一天早晚、重启都一样，换天大概率换一句。
extension PaydayMood {
    /// 这一档的全部台词；有的句子带上实际发薪日或剩余天数。
    func quips(for countdown: PaydayCountdown) -> [String] {
        switch self {
        case .farOff:
            [
                "钱包冬眠中，省着点花",
                "离发薪还远，奶茶先戒一戒",
                "余额紧张，泡面也挺香",
                "日子还长，慢慢拉磨",
            ]
        case .withinTwoWeeks:
            [
                "撑住，\(countdown.next.day) 号\(Format.weekdayNames[countdown.next.weekday - 1])就发钱",
                "再拉 \(countdown.days) 天磨，工资就到账",
                "发薪日已经看得见了",
                "熬了这么久，不差这几天",
            ]
        case .soon:
            [
                "再坚持\(countdown.days == 2 ? "两" : "三")天，钱在路上了",
                "工资正在打包，马上发货",
                "已经能闻到工资的味道了",
            ]
        case .tomorrow:
            [
                "购物车可以先加满了",
                "今晚早点睡，明早看短信",
                "最后一班岗，站好就行",
            ]
        case .payday:
            [
                "先存一笔，再犒劳自己",
                "到账了！今天腰板挺直",
                "工资到手，奶茶加料",
                "今天的牛马最值钱",
            ]
        case .justPaid:
            [
                "钱包鼓鼓，别一口气花光",
                "趁还有钱，先把房租交了",
                "新一轮拉磨开始了",
                "余额正好，理性消费",
            ]
        }
    }

    /// 这一档有几句台词 (不依赖具体日期)。
    var quipCount: Int {
        quips(for: PaydayCountdown(days: 0, next: Self.epoch, previous: Self.epoch.adding(days: -30))).count
    }

    /// `day` 这天的台词：按日期算一个固定的伪随机下标，不用 `Hasher` (每次启动的种子不同)。
    func quip(for countdown: PaydayCountdown, on day: LocalDate) -> String {
        let quips = quips(for: countdown)
        return quips[Int(Self.mix(UInt64(bitPattern: Int64(day.days(since: Self.epoch)))) % UInt64(quips.count))]
    }

    private static let epoch = LocalDate(year: 1970, month: 1, day: 1)

    /// SplitMix64 的末段混合：相邻日期也会得到差别很大的值。
    private static func mix(_ seed: UInt64) -> UInt64 {
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
