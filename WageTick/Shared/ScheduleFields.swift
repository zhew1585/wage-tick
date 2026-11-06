import SwiftUI
import WageCore

/// 作息表单的草稿：时间选择器用 `Date` 表示时刻，关闭饭点时仍记住饭点时段，再打开不用重填。
/// 引导与设置页共用，保证两处的作息输入一致。
/// 改了上下班时，饭点按原来的长度自动挪到新上下班的正中间 (`LunchBreak.centered`)；放不下时关掉饭点。
struct ScheduleDraft: Equatable {
    var start: Date { didSet { recenterLunch() } }
    var end: Date { didSet { recenterLunch() } }
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

    private mutating func recenterLunch() {
        let length = Int(lunchEnd.timeIntervalSince(lunchStart) / 60)
        guard let lunch = LunchBreak.centered(
            between: TimeOfDay(pickerDate: start), and: TimeOfDay(pickerDate: end),
            length: length > 0 ? length : LunchBreak.default.minutes
        ) else {
            lunchEnabled = false
            return
        }
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

/// 计划上下班与饭点的输入 (设计稿 P1 引导 · 2 作息)：上下班一行两格，饭点开关，打开后饭点时段一行两格。
struct ScheduleFields: View {
    @Binding var draft: ScheduleDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            HStack(spacing: Spacing.s12) {
                Field("计划上班") { TimeInput(selection: $draft.start) }
                Field("计划下班") { TimeInput(selection: $draft.end) }
            }
            ToggleRow("饭点", isOn: $draft.lunchEnabled)
            if draft.lunchEnabled {
                HStack(spacing: Spacing.s12) {
                    Field("饭点开始") { TimeInput(selection: $draft.lunchStart) }
                    Field("饭点结束") { TimeInput(selection: $draft.lunchEnd) }
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
