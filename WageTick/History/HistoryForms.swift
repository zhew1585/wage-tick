import SwiftUI
import WageCore

/// 补记或修改一段白干 (PRD 4.4.3 #5、F11)，与改工资表单同一套大胆版样式 (站酷体标题、底部胶囊按钮)：这一天的开始时刻，结束时刻可以落在次日 (跨过零点)。
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
            HistoryFormTitle(isEditing ? "改一段白干" : "补记白干")
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
            HistoryFormButtons(cancel: dismiss, save: save)
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

/// 改某个月的工资 (PRD 4.2.1 #2、4.6.1)：上方「月薪 | 日薪」切换 (issue #16)，下面金额，只影响该月。
/// 校验与提示与设置页同一套 (`Validation.salary`)；样式同补记白干表单。
struct SalaryFormView: View {
    let month: YearMonth
    /// 如「2026年1月」。
    let title: String
    /// 是否本月：本月的新月薪未来月份也沿用 (PRD 4.2.1 #3)，过去的月份只改这个月。
    let isCurrentMonth: Bool
    let actions: PanelActions
    let dismiss: () -> Void

    @State private var text: String
    @State private var basis: PayBasis
    @State private var errorMessage: String?

    init(
        month: YearMonth, title: String, isCurrentMonth: Bool, current: Decimal, basis: PayBasis, actions: PanelActions,
        dismiss: @escaping () -> Void
    ) {
        self.month = month
        self.title = title
        self.isCurrentMonth = isCurrentMonth
        self.actions = actions
        self.dismiss = dismiss
        _text = State(initialValue: NSDecimalNumber(decimal: current).stringValue)
        _basis = State(initialValue: basis)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s14) {
            HistoryFormTitle("\(title)的工资")
            Text(hint).font(AppFont.caption).foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: Spacing.s6) {
                PayBasisSwitch(selection: basis) { basis = $0 }
                Field(nil, text: $text, suffix: basis.unit)
                    .onSubmit(save)
            }
            if let errorMessage {
                Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
            HistoryFormButtons(cancel: dismiss, save: save)
        }
        .padding(Spacing.screen)
        .frame(width: 280)
        .background(Palette.bg)
        .onChange(of: text) { errorMessage = nil }
        .onChange(of: basis) { errorMessage = nil }
    }

    private var hint: String {
        let scope = isCurrentMonth ? "整月生效，之后的月份也沿用" : "只改这个月，其他月份不受影响"
        return basis == .daily ? scope + "。按天算时周末和法定节假日都是 0" : scope
    }

    /// 不是数字的写法按 0 交给核心，得到「月薪得是个正数」或「日薪得是个正数」。
    private func save() {
        do {
            try actions.send(.setSalary(month, SalaryText.parse(text) ?? 0, basis: basis))
            dismiss()
        } catch {
            errorMessage = error.message
        }
    }
}

/// 历史里小表单 (补记白干、改工资) 的标题：站酷体 20 号墨色。
private struct HistoryFormTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).font(AppFont.fun(20)).foregroundStyle(Palette.ink)
    }
}

/// 历史里小表单底部的两颗胶囊按钮：「算了」墨色描边 (Esc)，「保存」墨色实心 (回车)，各占一半。
private struct HistoryFormButtons: View {
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Button("算了", action: cancel)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.pill(.outline))
            Button(action: save) {
                Label { Text("保存") } icon: { PhosphorIcon(.check, size: 16) }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.pill(.ink))
        }
        .padding(.top, Spacing.s4)
    }
}
