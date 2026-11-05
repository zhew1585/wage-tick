import Foundation

/// 判定来源 (PRD 4.2.2 应出勤日字段)：这一天是否应出勤由哪条规则决定，历史单日详情里展示。
public enum AttendanceSource: Sendable, Equatable, CaseIterable {
    /// 双休：不在节假日表里，周一至周五应出勤、周六日不应出勤 (含节假日数据缺失的年份)。
    case weekend
    /// 法定节假日：不应出勤。
    case publicHoliday
    /// 调休上班：应出勤，即使落在周六日。
    case makeupDay
    /// 单日覆盖：牛马手动改成上班日或不上班日。预留给 #15，本票不会出现。
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
    /// 某天的判定来源，与 `isAttendanceDay` 同一判定顺序：调休上班日 > 法定节假日 > 周六日 > 其余。
    func source(on date: LocalDate) -> AttendanceSource {
        switch holidays.kind(on: date) {
        case .makeupDay: .makeupDay
        case .holiday: .publicHoliday
        case nil: .weekend
        }
    }
}
