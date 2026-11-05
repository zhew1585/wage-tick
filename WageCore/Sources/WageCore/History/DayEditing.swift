import Foundation

// 单日详情里的编辑入口 (PRD 4.6.1 可编辑内容、F11，#15)：哪些能改、不能改的原因、表单预填与预览起点。
// 外壳按它决定入口可用与否、显示原因，表单预览照旧走「草稿试算后再取快照」。

/// 一个编辑入口：可用时带着表单要用的内容，不可用时带着展示给牛马的原因。
public enum EditEntry<Content: Sendable & Equatable>: Sendable, Equatable {
    case available(Content)
    /// 原因与命令被拒时的提示相同，如「今天本来就不上班」(PRD 4.3.5 #8)。
    case unavailable(reason: String)

    public var isAvailable: Bool { content != nil }

    /// 可用时的内容，否则为 nil。
    public var content: Content? {
        if case .available(let content) = self { content } else { nil }
    }

    /// 不可用的原因，可用时为 nil。
    public var reason: String? {
        if case .unavailable(let reason) = self { reason } else { nil }
    }
}

/// 某一天的编辑入口。可编辑范围：过去和今天可改扣钱、请假、白干段、单日覆盖；未来只能请假和单日覆盖。
public struct DayEditing: Sendable, Equatable {
    /// 记扣钱 (新记、修改)：可用时为表单预览的起点 (这天的今日上限)。删除不受限，见 `HistoryDayDetail.deductions`。
    public let deduction: EditEntry<DeductionEntry>
    /// 请假：可用时为这天的请假表单 (已有请假、汇总)。
    public let leave: EditEntry<LeaveForm>
    /// 补记白干段：可用时为新补记一段的预填时段 (计划下班起 1 小时)。
    public let unpaidWork: EditEntry<UnpaidWorkInput>
    /// 这天已有的白干段，按开始时刻先后，可改删。
    public let unpaidWorkItems: [UnpaidWorkItem]
    /// 单日覆盖按钮：没有覆盖时改成相反的一种，有覆盖时撤销。任何日期都有。
    public let overrideButton: EditButton
}

/// 单日详情里的一段白干。
public struct UnpaidWorkItem: Sendable, Equatable, Identifiable {
    /// 修改、删除命令用的编号 (这天的第几段)。
    public let index: Int
    /// 展示文字，与 `HistoryDayDetail.unpaidWork` 同一行。
    public let line: HistoryLine
    /// 修改表单的预填时段；计时中的那段不能改，为 nil。
    public let input: UnpaidWorkInput?

    public var id: Int { index }
}

/// 一个按钮：文案与点下后要发的命令，外壳原样展示、原样发出。
public struct EditButton: Sendable, Equatable {
    public let title: String
    public let command: Command

    public init(title: String, command: Command) {
        self.title = title
        self.command = command
    }
}

extension Snapshot {
    /// 某一天在月日历里的样子与详情；不在安装当月至本月之间时为 nil。只在调用时推导 (整月)。
    /// 历史编辑的表单试算后用它取这一天的预览。
    public func historyDay(_ date: LocalDate) -> HistoryDay? {
        historyMonth(date.yearMonth)?.days.first { $0.date == date }
    }
}

extension HistoryLedger {
    func editing(_ day: DayLedger, unpaidWorkLines: [HistoryLine]) -> DayEditing {
        let isFuture = day.date > today
        let restReason = CommandError.notAttendanceDay.message
        let futureReason = CommandError.futureDate.message
        let deduction: EditEntry<DeductionEntry> = if let settlement = day.settlement {
            isFuture
                ? .unavailable(reason: futureReason)
                : .available(DeductionEntry(settlement: settlement, capTitle: incomeTitle(day.date)))
        } else {
            .unavailable(reason: restReason)
        }
        let leave: EditEntry<LeaveForm> = day.settlement.map { .available(leaveForm(day, settlement: $0)) }
            ?? .unavailable(reason: restReason)
        return DayEditing(
            deduction: deduction,
            leave: leave,
            unpaidWork: isFuture ? .unavailable(reason: futureReason) : .available(unpaidWorkDraft(day.date)),
            unpaidWorkItems: zip(day.unpaidWork, unpaidWorkLines).enumerated().map { index, pair in
                UnpaidWorkItem(index: index, line: pair.1, input: unpaidWorkInput(pair.0.segment, on: day.date))
            },
            overrideButton: overrideButton(day)
        )
    }

    /// 这天的请假表单，汇总里的收入项标题与详情同口径 (见 `incomeTitle`)。
    private func leaveForm(_ day: DayLedger, settlement: DaySettlement) -> LeaveForm {
        let capTitle = incomeTitle(day.date)
        return LeaveForm(
            leave: day.record?.leave, settlement: settlement, schedule: inputs.profile.schedule(on: day.date), on: day.date,
            planTitle: LeaveForm.planTitle(day.date, today: today), capTitle: capTitle, now: inputs.now
        )
    }

    /// 新补记一段的预填：这天作息的计划下班起 1 小时，最晚 23:59。
    private func unpaidWorkDraft(_ date: LocalDate) -> UnpaidWorkInput {
        let start = inputs.profile.schedule(on: date).end
        let end = min(start.minutesSinceMidnight + 60, 23 * 60 + 59)
        return UnpaidWorkInput(start: start, end: TimeOfDay(hour: end / 60, minute: end % 60))
    }

    /// 已有一段的修改预填；计时中的不能改。该停没推进的那段按 23:59:59 停止预填。
    private func unpaidWorkInput(_ segment: UnpaidWorkSegment, on date: LocalDate) -> UnpaidWorkInput? {
        let now = inputs.now
        guard !segment.isRunning(on: date, now: now) else { return nil }
        let end = segment.end ?? now.unpaidWorkCutoff(on: date)
        return UnpaidWorkInput(start: now.timeOfDay(of: segment.start), end: now.timeOfDay(of: end))
    }

    private func overrideButton(_ day: DayLedger) -> EditButton {
        let edit: (String, DayEdit) = if day.record?.override != nil {
            ("撤销单日覆盖", .clearOverride)
        } else if day.isAttendanceDay {
            ("改成不上班日", .setOverride(.dayOff))
        } else {
            ("改成上班日", .setOverride(.attendanceDay))
        }
        return EditButton(title: edit.0, command: .editDay(day.date, edit.1))
    }
}

private extension Moment {
    /// 绝对时刻在此刻所在时区里的时分 (秒数舍去)。
    func timeOfDay(of date: Date) -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}
