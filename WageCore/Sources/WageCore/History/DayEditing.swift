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
    /// 补记白干段：可用时为新补记一段的预填时段 (计划下班起 1 小时，可能跨过零点到次日)。
    public let unpaidWork: EditEntry<UnpaidWorkInput>
    /// 白干段表单里结束日期的选项：当天、次日……直到这天的自动停止时刻那天 (PRD 4.4.3 #3)。补记与修改共用。
    public let unpaidWorkEndDays: [UnpaidWorkEndDay]
    /// 这天已有的白干段，按开始时刻先后，可改删。
    public let unpaidWorkItems: [UnpaidWorkItem]
    /// 单日覆盖按钮：没有覆盖时改成相反的一种，有覆盖时撤销。任何日期都有。
    public let overrideButton: EditButton
}

/// 白干段表单里结束日期的一个选项。
public struct UnpaidWorkEndDay: Sendable, Equatable, Identifiable {
    /// 开始那天之后第几天，即 `UnpaidWorkInput.endDayOffset`。
    public let offset: Int
    /// 如「当天」「次日」「11月9日 周一」。
    public let label: String

    public var id: Int { offset }
}

/// 单日详情里的一段白干。
public struct UnpaidWorkItem: Sendable, Equatable, Identifiable {
    /// 修改、删除命令用的编号 (这天的第几段)。
    public let index: Int
    /// 展示文字，与 `HistoryDayDetail.unpaidWork` 同一行。
    public let line: HistoryLine
    /// 修改表单的预填时段；计时中的那段不能改，为 nil。
    public let input: UnpaidWorkInput?
    /// 这一段倒贴的钱 (时长 × 时薪，PRD 4.4.3 #4)，如「倒贴 ¥214.29」；计时中的算到此刻。
    public let loss: String

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
        let items = zip(day.unpaidWork, unpaidWorkLines).enumerated().map { index, pair in
            UnpaidWorkItem(
                index: index, line: pair.1, input: unpaidWorkInput(pair.0.segment, on: day.date),
                loss: "倒贴 \(Format.money(clock.owed(on: day.date, milliseconds: pair.0.milliseconds)))"
            )
        }
        return DayEditing(
            deduction: deduction,
            leave: leave,
            unpaidWork: isFuture ? .unavailable(reason: futureReason) : .available(unpaidWorkDraft(day.date)),
            unpaidWorkEndDays: isFuture ? [] : unpaidWorkEndDays(day.date, covering: items.compactMap(\.input)),
            unpaidWorkItems: items,
            overrideButton: overrideButton(day)
        )
    }

    /// 这天的请假表单，汇总里的收入项标题与详情同口径 (见 `incomeTitle`)。
    private func leaveForm(_ day: DayLedger, settlement: DaySettlement) -> LeaveForm {
        let capTitle = incomeTitle(day.date)
        return LeaveForm(
            leave: day.record?.leave, settlement: settlement, schedule: day.schedule,
            planTitle: LeaveForm.planTitle(day.date, today: today), capTitle: capTitle
        )
    }

    /// 新补记一段的预填：这天作息的计划下班起 1 小时，过了零点就落到次日。
    private func unpaidWorkDraft(_ date: LocalDate) -> UnpaidWorkInput {
        let start = inputs.profile.schedule(on: date).end
        let end = start.minutesSinceMidnight + 60
        return UnpaidWorkInput(start: start, end: TimeOfDay(minutesSinceMidnight: end % 1440), endDayOffset: end / 1440)
    }

    /// 结束日期的选项：从当天到这天的自动停止时刻那天；已有的段结束得更晚 (如之后改了作息或请假) 时也覆盖到，修改表单能原样预填。
    private func unpaidWorkEndDays(_ date: LocalDate, covering inputs: [UnpaidWorkInput]) -> [UnpaidWorkEndDay] {
        let bound = Moment(date: clock.autoStop(after: date), timeZone: self.inputs.now.timeZone).localDate.days(since: date)
        let last = ([bound] + inputs.map(\.endDayOffset)).max() ?? bound
        return (0...max(0, last)).map { offset in
            let label = switch offset {
            case 0: "当天"
            case 1: "次日"
            default: Format.date(date.adding(days: offset), relativeTo: today)
            }
            return UnpaidWorkEndDay(offset: offset, label: label)
        }
    }

    /// 已有一段的修改预填；计时中的不能改。该停没推进的那段按自动停止时刻预填。
    private func unpaidWorkInput(_ segment: UnpaidWorkSegment, on date: LocalDate) -> UnpaidWorkInput? {
        guard !clock.isRunning(segment, on: date) else { return nil }
        let now = inputs.now
        let end = clock.end(of: segment, on: date)
        let endDay = Moment(date: end, timeZone: now.timeZone).localDate
        return UnpaidWorkInput(
            start: now.timeOfDay(of: segment.start), end: now.timeOfDay(of: end), endDayOffset: max(0, endDay.days(since: date))
        )
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
