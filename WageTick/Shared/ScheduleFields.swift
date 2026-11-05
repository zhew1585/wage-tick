import SwiftUI
import WageCore

/// 作息表单的草稿：时间选择器用 `Date` 表示时刻，关闭午休时仍记住午休时段，再打开不用重填。
/// 引导与设置页共用，保证两处的作息输入一致。
struct ScheduleDraft: Equatable {
    var start: Date
    var end: Date
    var lunchEnabled: Bool
    var lunchStart: Date
    var lunchEnd: Date

    init(_ schedule: WorkSchedule) {
        let lunch = schedule.lunch ?? .default
        start = schedule.start.pickerDate
        end = schedule.end.pickerDate
        lunchEnabled = schedule.lunch != nil
        lunchStart = lunch.start.pickerDate
        lunchEnd = lunch.end.pickerDate
    }

    /// 草稿对应的作息，未经校验，交给核心的 `Validation` 或命令把关。
    var schedule: WorkSchedule {
        WorkSchedule(
            start: TimeOfDay(pickerDate: start),
            end: TimeOfDay(pickerDate: end),
            lunch: lunchEnabled ? LunchBreak(start: TimeOfDay(pickerDate: lunchStart), end: TimeOfDay(pickerDate: lunchEnd)) : nil
        )
    }
}

/// 计划上下班与午休的输入 (设计稿 P1 引导 · 2 作息)：上下班一行两格，午休开关，打开后午休时段一行两格。
struct ScheduleFields: View {
    @Binding var draft: ScheduleDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            HStack(spacing: Spacing.s12) {
                Field("计划上班") { TimeInput(selection: $draft.start) }
                Field("计划下班") { TimeInput(selection: $draft.end) }
            }
            ToggleRow("午休", isOn: $draft.lunchEnabled)
            if draft.lunchEnabled {
                HStack(spacing: Spacing.s12) {
                    Field("午休开始") { TimeInput(selection: $draft.lunchStart) }
                    Field("午休结束") { TimeInput(selection: $draft.lunchEnd) }
                }
            }
        }
    }
}

/// 时间选择器用 `Date` 表示时刻，这里与核心的 `TimeOfDay` 互转。作息表单与白干段表单共用。
extension TimeOfDay {
    init(pickerDate: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: pickerDate)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    var pickerDate: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
