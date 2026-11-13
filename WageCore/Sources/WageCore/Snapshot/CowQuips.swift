import Foundation

/// 悬浮小牛气泡里的台词：每个场景 3 至 5 句，每天按日期固定挑一句。
/// 同一天早晚、重启都一样，换天大概率换一句；同一天换了场景 (如上班到下班) 跟着换一句。
extension CowScene {
    /// 这个场景的全部台词；快发薪的句子带上剩余天数。
    var quips: [String] {
        switch self {
        case .beforeWork:
            [
                "再眯五分钟，就五分钟",
                "工位还没醒，我也没醒",
                "今天的磨，还在路上",
                "咖啡续上，准备开工",
            ]
        case .working:
            [
                "认真摸鱼，偶尔拉磨",
                "每一秒都在进账",
                "稳住，别让老板看见",
                "拉磨也要有节奏",
            ]
        case .lunch:
            [
                "干饭不积极，思想有问题",
                "吃饱了才有力气摸鱼",
                "这一口，是我应得的",
                "饭点不谈工作",
            ]
        case .onLeave:
            [
                "暂时离线，马上回来",
                "偷得半日闲",
                "请假的时间格外珍贵",
            ]
        case .offWork:
            [
                "下班了，谁也别找我",
                "今天的磨拉完了",
                "躺平是对自己最好的奖励",
                "电脑一合，烦恼全无",
            ]
        case .restDay:
            [
                "今天不营业",
                "阳光正好，工作勿扰",
                "休息日就该晒太阳",
                "手机静音，世界安静",
            ]
        case .unpaidWork:
            [
                "这一分钟，没人给钱",
                "老板的梦想，我的加班",
                "白干也要干得漂亮",
                "早点收工吧，牛马",
            ]
        case .paydaySoon(days: 1):
            [
                "购物车可以先加满了",
                "今晚早点睡，明早看短信",
                "最后一班岗，站好就行",
            ]
        case .paydaySoon(let days):
            [
                "再坚持\(days == 2 ? "两" : "三")天，钱在路上了",
                "工资正在打包，马上发货",
                "已经能闻到工资的味道了",
            ]
        case .payday:
            [
                "先存一笔，再犒劳自己",
                "到账了！今天腰板挺直",
                "工资到手，奶茶加料",
                "今天的牛马最值钱",
            ]
        }
    }

    /// `day` 这天的台词：按日期算一个固定的伪随机下标，不用 `Hasher` (每次启动的种子不同)。
    func quip(on day: LocalDate) -> String {
        Self.pick(quips, on: day)
    }

    /// 首页头图气泡里的短台词 (设计稿「大胆风格」，三到五个字，不压到左边的大数字)；
    /// 只给不写倒计时的场景 (未上班、已下班、休息日、发薪当天)，其余场景为空，气泡写倒计时。挑法同 `quip(on:)`。
    var heroQuips: [String] {
        switch self {
        case .beforeWork: ["再睡五分钟", "还没睡醒", "马上就到"]
        case .offWork: ["躺平！", "收工！", "下班啦"]
        case .restDay: ["谁也别找我", "今天不营业", "晒太阳中"]
        case .payday: ["发工资啦", "钱到账啦", "今天最值钱"]
        default: []
        }
    }

    /// `day` 这天的头图短台词；这个场景没有短台词时为 nil。
    func heroQuip(on day: LocalDate) -> String? {
        heroQuips.isEmpty ? nil : Self.pick(heroQuips, on: day)
    }

    /// 按日期算一个固定的伪随机下标挑一句。
    private static func pick(_ quips: [String], on day: LocalDate) -> String {
        quips[Int(mix(UInt64(bitPattern: Int64(day.days(since: epoch)))) % UInt64(quips.count))]
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
