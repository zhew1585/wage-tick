import SwiftUI
import WageCore

/// 补记或修改一段白干 (PRD 4.4.3 #5、F11)：这一天的开始时刻，结束时刻可以落在次日 (跨过零点)。
/// 结束日期的选项、校验与提示都来自核心；只有当天一个选项时不显示结束日期。
struct UnpaidWorkFormView: View {
    /// 新补记 (带预填时段) 还是修改第 `index` 段。
    enum Request: Identifiable {
        case add(UnpaidWorkInput)
        case edit(index: Int, UnpaidWorkInput)

        var id: String {
            switch self {
            case .add: "add"
            case .edit(let index, _): "edit-\(index)"
            }
        }

        var input: UnpaidWorkInput {
            switch self {
            case .add(let input), .edit(_, let input): input
            }
        }
    }

    let request: Request
    let date: LocalDate
    /// 结束日期的选项 (`DayEditing.unpaidWorkEndDays`)。
    let endDays: [UnpaidWorkEndDay]
    let actions: PanelActions
    let dismiss: () -> Void

    @State private var start: Date
    @State private var end: Date
    @State private var endDayOffset: Int
    @State private var errorMessage: String?

    init(request: Request, date: LocalDate, endDays: [UnpaidWorkEndDay], actions: PanelActions, dismiss: @escaping () -> Void) {
        self.request = request
        self.date = date
        self.endDays = endDays
        self.actions = actions
        self.dismiss = dismiss
        _start = State(initialValue: request.input.start.pickerDate)
        _end = State(initialValue: request.input.end.pickerDate)
        _endDayOffset = State(initialValue: request.input.endDayOffset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s14) {
            Text(isEditing ? "改一段白干" : "补记白干").font(AppFont.sheetTitle).foregroundStyle(Palette.ink)
            HStack(spacing: Spacing.s12) {
                Field("开始") { TimeInput(selection: $start) }
                Field("结束") { TimeInput(selection: $end) }
            }
            if endDays.count > 1 {
                Field("结束日期") { EndDayInput(options: endDays, selection: $endDayOffset) }
            }
            if let errorMessage {
                Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            HStack(spacing: Spacing.s8) {
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.secondary(fullWidth: true))
                Button(action: save) { Label("保存", systemImage: "checkmark") }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primary(fullWidth: true))
            }
        }
        .padding(Spacing.screen)
        .frame(width: 280)
        .background(Palette.bg)
        .onChange(of: start) { errorMessage = nil }
        .onChange(of: end) { errorMessage = nil }
        .onChange(of: endDayOffset) { errorMessage = nil }
    }

    private var isEditing: Bool {
        if case .edit = request { true } else { false }
    }

    private func save() {
        let input = UnpaidWorkInput(start: TimeOfDay(pickerDate: start), end: TimeOfDay(pickerDate: end), endDayOffset: endDayOffset)
        let edit: DayEdit = switch request {
        case .add: .addUnpaidWork(input)
        case .edit(let index, _): .editUnpaidWork(index: index, input)
        }
        do {
            try actions.send(.editDay(date, edit))
            dismiss()
        } catch {
            errorMessage = error.message
        }
    }
}

/// 白干段结束日期的选择，放进 `Field` 里用，外观同 `TimeInput`：当前选项的文字，右侧一个向下箭头，点开是选项菜单。
private struct EndDayInput: View {
    let options: [UnpaidWorkEndDay]
    @Binding var selection: Int

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button(option.label) { selection = option.offset }
            }
        } label: {
            HStack(spacing: Spacing.s8) {
                Text(options.first { $0.offset == selection }?.label ?? "")
                    .font(AppFont.fieldText)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                PhosphorIcon(.caretDown, size: 12).foregroundStyle(Palette.muted)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

/// 改某个月的月薪 (PRD 4.2.1 #2、4.6.1)：只影响该月。校验与提示与设置页同一套 (`Validation.monthlySalary`)。
struct SalaryFormView: View {
    let month: YearMonth
    /// 如「2026年1月」。
    let title: String
    /// 是否本月：本月的新月薪未来月份也沿用 (PRD 4.2.1 #3)，过去的月份只改这个月。
    let isCurrentMonth: Bool
    let actions: PanelActions
    let dismiss: () -> Void

    @State private var text: String
    @State private var errorMessage: String?

    init(
        month: YearMonth, title: String, isCurrentMonth: Bool, current: Decimal, actions: PanelActions,
        dismiss: @escaping () -> Void
    ) {
        self.month = month
        self.title = title
        self.isCurrentMonth = isCurrentMonth
        self.actions = actions
        self.dismiss = dismiss
        _text = State(initialValue: NSDecimalNumber(decimal: current).stringValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s14) {
            Text("\(title)的月薪").font(AppFont.sheetTitle).foregroundStyle(Palette.ink)
            Text(hint).font(AppFont.caption).foregroundStyle(Palette.muted)
            Field("月薪", text: $text, suffix: "元")
                .onSubmit(save)
            if let errorMessage {
                Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            HStack(spacing: Spacing.s8) {
                Button("取消", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.secondary(fullWidth: true))
                Button(action: save) { Label("保存", systemImage: "checkmark") }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.primary(fullWidth: true))
            }
        }
        .padding(Spacing.screen)
        .frame(width: 280)
        .background(Palette.bg)
        .onChange(of: text) { errorMessage = nil }
    }

    private var hint: String {
        isCurrentMonth ? "整月生效，之后的月份也沿用" : "只改这个月，其他月份不受影响"
    }

    /// 不是数字的写法按 0 交给核心，得到「月薪得是个正数」。
    private func save() {
        do {
            try actions.send(.setMonthlySalary(month, SalaryText.parse(text) ?? 0))
            dismiss()
        } catch {
            errorMessage = error.message
        }
    }
}
