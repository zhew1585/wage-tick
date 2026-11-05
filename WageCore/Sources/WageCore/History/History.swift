import Foundation

/// 历史 (PRD 4.6.1) 的推导输入。
/// 快照只带着它，不推导：菜单栏每秒刷新多次，历史只在历史窗口调用 `historyMonths()`、`historyMonth(_:)` 时才推导。
struct HistorySource: Sendable, Equatable {
    let profile: Profile
    let dayRecords: [DayRecord]
    /// 同一快照里今天的推导结果：本月结算总额直接取它的本月累计 (AC-HIS-01)。
    let today: Today
    let now: Moment
    let holidays: HolidayTable

    /// 快照相等只看推导结果：按推导出的每个月比较，不比较原始输入
    /// (如该在 23:59:59 自动停止、还没推进的白干段，与推进后的推导一致)。只在比较时推导，外壳不比较快照。
    static func == (lhs: HistorySource, rhs: HistorySource) -> Bool {
        lhs.derived == rhs.derived
    }

    /// 安装当月至本月每个月的日历。
    private var derived: [HistoryMonth] {
        let ledger = HistoryLedger(self)
        return ledger.months.map(ledger.month)
    }
}

extension Snapshot {
    /// 历史月列表 (F10)：安装当月至今每个月的汇总，按月倒序 (PRD 4.6.1、AC-PRE-02)。未完成引导时为空。
    /// 每次调用都重新推导，外壳只在历史窗口打开时调用。
    public func historyMonths() -> [HistoryMonthSummary] {
        guard let history else { return [] }
        let ledger = HistoryLedger(history)
        return ledger.months.reversed().map { ledger.summary(ledger.ledger(for: $0)) }
    }
}

/// 月列表里的一个月 (F10)，文字已格式化好，外壳原样展示。
public struct HistoryMonthSummary: Sendable, Equatable, Identifiable {
    public let month: YearMonth
    /// 如「2026年2月」。
    public let title: String
    /// 是否本月：本月结算总额等于本月累计 (AC-HIS-01)。
    public let isCurrentMonth: Bool
    /// 结算总额、应出勤日数、扣款合计、请假天数、白干时长 (AC-HIS-02)，按此顺序。
    public let stats: [StatItem]

    public var id: YearMonth { month }
}

/// 一次历史推导用到的规则与索引，推导时现建现用。
struct HistoryLedger {
    let source: HistorySource
    let rule: AttendanceRule
    /// 按日期索引的日记录，逐日推导时免得每天都扫一遍。
    let records: [LocalDate: DayRecord]

    init(_ source: HistorySource) {
        self.source = source
        rule = AttendanceRule(holidays: source.holidays)
        records = Dictionary(source.dayRecords.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 安装当月至本月，按月升序；系统时间被拨回到安装月之前时为空 (PRD 4.3.5 #11)。
    var months: [YearMonth] {
        let current = source.today.date.yearMonth
        return Array(sequence(first: source.profile.installDate.yearMonth) { $0.next }.prefix { $0 <= current })
    }
}

extension YearMonth {
    /// 下一个月。
    var next: YearMonth {
        month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1)
    }
}
