import Foundation

/// 判定来源 (PRD 4.2.2 应出勤日字段)：这一天是否应出勤由哪条规则决定，历史单日详情里展示。
public enum AttendanceSource: Sendable, Equatable, CaseIterable {
    /// 双休：不在节假日表里，周一至周五应出勤、周六日不应出勤 (含节假日数据缺失的年份)。
    case weekend
    /// 法定节假日：不应出勤。
    case publicHoliday
    /// 调休上班：应出勤，即使落在周六日。
    case makeupDay
    /// 单日覆盖：牛马手动改成上班日或不上班日 (#15)。
    case override

    /// 展示文案。
    public var label: String {
        switch self {
        case .weekend: "双休"
        case .publicHoliday: "法定节假日"
        case .makeupDay: "调休上班"
        case .override: "单日覆盖"
        }
    }
}

extension AttendanceRule {
    /// 某天的判定来源，与 `isAttendanceDay` 同一判定顺序：单日覆盖 > 调休上班日 > 法定节假日 > 周六日 > 其余。
    func source(on date: LocalDate) -> AttendanceSource {
        if holidays.overrides[date] != nil { return .override }
        return switch holidays.kind(on: date) {
        case .makeupDay: .makeupDay
        case .holiday: .publicHoliday
        case nil: .weekend
        }
    }
}

extension AttendanceRule {
    /// 当月日薪 = 当月月薪 ÷ 当月应出勤日数 (PRD 4.2.4)，今天与历史同用。
    /// 应出勤日数为 0 时没有日薪，记 0，结算与本月累计随之为 0；面板提示见 `TodayPanel.notices` (PRD 4.3.5 #19)。
    func dailyWage(in month: YearMonth, profile: Profile) -> Decimal {
        let count = attendanceDayCount(in: month)
        return count > 0 ? profile.salary(for: month) / Decimal(count) : 0
    }
}
