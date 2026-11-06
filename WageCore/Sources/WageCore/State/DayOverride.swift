import Foundation

/// 单日覆盖 (PRD 4.2.2)：牛马手动把某一天改成上班日或不上班日，是应出勤日判定的第 1 优先级。
/// 存在日记录里，撤销即删掉。
public enum DayOverride: String, Sendable, Equatable, Codable {
    /// 上班日 (应出勤日)：即使落在周六日或法定节假日。
    case attendanceDay
    /// 不上班日：不应出勤，即使是调休上班日或周一至周五。
    case dayOff

    /// 是否应出勤。
    var isAttendanceDay: Bool { self == .attendanceDay }
}

extension HolidayTable {
    /// 把状态里的单日覆盖与各月的休息模式并入节假日表，供 `AttendanceRule` 判定 (PRD 4.2.2)。
    /// `apply`、`snapshot` 入口各并一次，下游所有拿着节假日表判定应出勤日的地方 (今天、本月累计、目标累计收入、历史) 都自动带上。
    /// 用状态当前的内容整体替换，重复调用结果不变。
    func overlaying(_ state: AppState) -> HolidayTable {
        var table = self
        table.overrides = Dictionary(
            state.dayRecords.compactMap { record in record.override.map { (record.date, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        table.restModes = state.profile?.restModes ?? []
        return table
    }
}
