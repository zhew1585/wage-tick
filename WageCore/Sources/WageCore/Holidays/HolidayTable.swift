import Foundation

/// 法定节假日数据里一天的类型 (PRD 4.2.2)。
public enum HolidayKind: Sendable, Equatable {
    /// 法定节假日：不应出勤。
    case holiday
    /// 调休上班日：应出勤，即使落在周六日。
    case makeupDay
}

/// 节假日表：由节假日数据源适配器提供，作为参数注入 `snapshot`，核心不自己读文件或联网。
/// 不在表里的日子按休息模式判定；空表即只按休息模式 (没并入时为双休)。
public struct HolidayTable: Sendable, Equatable {
    /// 已知的法定节假日与调休上班日，可跨多个年份。
    public let days: [LocalDate: HolidayKind]
    /// 获取失败、数据缺失的年份：该年只按休息模式计算，今天落在其中时面板顶部提示 (PRD 4.3.5 #10)。
    public let missingYears: Set<Int>
    /// 单日覆盖 (PRD 4.2.2)：不来自数据源，由 `apply`、`snapshot` 入口从状态并入 (见 `overlaying(_:)`)，判定时优先于上面的一切。
    var overrides: [LocalDate: DayOverride] = [:]
    /// 各月的休息模式 (PRD 4.2.2)：同样不来自数据源，由入口从牛马配置并入，按月份升序；为空时一律双休 (引导前)。
    var restModes: [MonthlyRestMode] = []

    public init(days: [LocalDate: HolidayKind], missingYears: Set<Int> = []) {
        self.days = days
        self.missingYears = missingYears
    }

    /// 没有任何节假日数据，也没有缺失年份：只按休息模式，不提示。
    public static let empty = HolidayTable(days: [:])

    /// `date` 在节假日数据里的类型；不在表里为 nil。
    public func kind(on date: LocalDate) -> HolidayKind? {
        days[date]
    }

    /// `month` 采用的休息模式：该月及之前最近一次设置的；早于最早一条的月份按最早一条，没有任何记录时为双休。
    func restMode(for month: YearMonth) -> RestMode {
        (restModes.last { $0.month <= month } ?? restModes.first)?.mode ?? .twoDaysOff
    }

    /// 今天所在年份的数据缺失时，面板顶部的提示条文案 (AC-HOME-08)。
    func missingNotice(on today: LocalDate) -> String? {
        guard missingYears.contains(today.year) else { return nil }
        return "\(today.year)年的节假日数据没拿到，调休日请在日历里手动标记"
    }
}
