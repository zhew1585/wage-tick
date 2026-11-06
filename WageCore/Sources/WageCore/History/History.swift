import Foundation

/// 历史 (PRD 4.6.1) 的推导输入。
/// 快照只带着它，不推导：菜单栏每秒刷新多次，历史只在历史窗口调用 `historyMonths()`、`historyMonth(_:)` 时才推导。
struct HistoryInputs: Sendable, Equatable {
    let profile: Profile
    let dayRecords: [DayRecord]
    /// 同一快照里今天的推导结果：本月结算总额直接取它的本月累计 (AC-HIS-01)。
    let today: Today
    let now: Moment
    let holidays: HolidayTable

    /// 快照相等只看推导结果：按推导出的每个月比较，不比较原始输入
    /// (如该在下一次计划上班自动停止、还没推进的白干段，与推进后的推导一致)。
    /// 注意：每次比较都要把安装当月至本月整个推导一遍，不要在刷新热路径上比较快照。
    static func == (lhs: HistoryInputs, rhs: HistoryInputs) -> Bool {
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
        return ledger.months.reversed().map { ledger.summary(ledger.monthLedger(for: $0)) }
    }
}

/// 月列表里的一个月 (F10)，文字已格式化好，外壳原样展示。
public struct HistoryMonthSummary: Sendable, Equatable, Identifiable {
    public let month: YearMonth
    /// 如「2026年2月」。
    public let title: String
    /// 是否本月：本月结算总额等于本月累计 (AC-HIS-01)。
    public let isCurrentMonth: Bool
    /// 是否安装当月：最早的一个月，月中安装时前面的日子按满勤补齐 (AC-PRE-01)。
    public let isInstallMonth: Bool
    /// 结算总额 (AC-HIS-02)，如「¥19450」(设计稿放在月份右边)；本月等于本月累计 (AC-HIS-01)。
    public let total: String
    /// 应出勤日数，如「应出勤」「20 天」。
    public let attendance: HistoryFigure
    /// 扣款合计 (扣钱 + 请假扣薪)，不带负号，如「扣款」「¥550」；有扣款时 `isLoss`。
    public let deduction: HistoryFigure
    /// 请假天数 (按请掉的工时折算，全天计 1)，如「请假」「1.29 天」。
    public let leave: HistoryFigure
    /// 白干时长合计，如「白干」「1h30m」。
    public let unpaidWork: HistoryFigure

    /// 结算总额以外的四项，按设计稿顺序：应出勤、扣款、请假、白干。
    public var figures: [HistoryFigure] { [attendance, deduction, leave, unpaidWork] }

    public var id: YearMonth { month }

    /// 标题旁的标签：本月为「本月 · 进行中」，安装当月 (不是本月时) 为「安装当月」，其余为 nil。
    public var badge: String? {
        if isCurrentMonth { return "本月 · 进行中" }
        return isInstallMonth ? "安装当月" : nil
    }
}

/// 历史里的一项汇总数字：短标题 + 数值，如「扣款」「¥550」。
public struct HistoryFigure: Sendable, Equatable {
    public let title: String
    public let value: String
    /// 是亏掉的钱 (扣款不为零)：外壳用亏钱色。
    public let isLoss: Bool

    public init(title: String, value: String, isLoss: Bool = false) {
        self.title = title
        self.value = value
        self.isLoss = isLoss
    }
}

/// 一次历史推导用到的输入、规则与索引，推导时现建现用。
struct HistoryLedger {
    let inputs: HistoryInputs
    let rule: AttendanceRule
    /// 按日期索引的日记录，逐日推导时免得每天都扫一遍。
    let records: [LocalDate: DayRecord]
    /// 白干段的时长、结束时刻与自动停止，与今天的面板同一套推导。
    let clock: UnpaidWorkClock

    init(_ inputs: HistoryInputs) {
        self.inputs = inputs
        rule = AttendanceRule(holidays: inputs.holidays)
        records = Dictionary(inputs.dayRecords.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        clock = UnpaidWorkClock(profile: inputs.profile, rule: rule, dayRecords: inputs.dayRecords, now: inputs.now)
    }

    var today: LocalDate { inputs.today.date }

    /// 安装当月至本月，按月升序；系统时间被拨回到安装月之前时为空 (PRD 4.3.5 #11)。
    var months: [YearMonth] {
        Array(sequence(first: inputs.profile.installDate.yearMonth) { $0.next }.prefix { $0 <= today.yearMonth })
    }
}
