import Foundation

/// 日记录 (PRD 4.3.1)：某一天牛马手动产生的内容，推导内容一律不存。
/// 一天一条，以日期为标识，存在 `AppState.dayRecords` 里。
/// PRD 的其余字段 (单日覆盖、请假、扣钱记录) 由各自的票追加，读入时都可缺省。
public struct DayRecord: Sendable, Equatable, Codable {
    /// 白干段 (PRD 4.4.3)，1:N，按开始时刻先后排列。
    public internal(set) var unpaidWork: [UnpaidWorkSegment]

    private enum CodingKeys: String, CodingKey { case unpaidWork }

    init(unpaidWork: [UnpaidWorkSegment] = []) {
        self.unpaidWork = unpaidWork
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unpaidWork = try container.decodeIfPresent([UnpaidWorkSegment].self, forKey: .unpaidWork) ?? []
    }
}

/// 一段白干计时 (PRD 4.4.3)："我还没走"或"被迫营业"从开始到停止。
public struct UnpaidWorkSegment: Sendable, Equatable, Codable {
    public let start: Date
    /// 计时中为 nil。
    public internal(set) var end: Date?
    /// 疑似通宵：到 23:59:59 被自动停止时为 true (PRD 4.3.5 #12)。
    public internal(set) var suspectedAllNighter: Bool

    /// 文件里结束早于开始的段不拒绝读入 (那样整个状态文件都会被隔离)：推导时长时按 0 计。
    init(start: Date, end: Date? = nil, suspectedAllNighter: Bool = false) {
        self.start = start
        self.end = end
        self.suspectedAllNighter = suspectedAllNighter
    }
}
