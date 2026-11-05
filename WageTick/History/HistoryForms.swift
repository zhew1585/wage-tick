import SwiftUI
import WageCore

/// 补记或修改一段白干 (PRD 4.4.3 #5、F11)：这一天之内的开始、结束时刻。校验与提示都来自核心。
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
    let actions: PanelActions
    let dismiss: () -> Void

    @State private var start: Date
    @State private var end: Date
    @State private var errorMessage: String?

    init(request: Request, date: LocalDate, actions: PanelActions, dismiss: @escaping () -> Void) {
        self.request = request
        self.date = date
        self.actions = actions
        self.dismiss = dismiss
        _start = State(initialValue: request.input.start.pickerDate)
        _end = State(initialValue: request.input.end.pickerDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "改一段白干" : "补记白干").font(.title3.bold())
            Form {
                DatePicker("开始", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: $end, displayedComponents: .hourAndMinute)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            HStack {
                Button("取消", action: dismiss).keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onChange(of: start) { errorMessage = nil }
        .onChange(of: end) { errorMessage = nil }
    }

    private var isEditing: Bool {
        if case .edit = request { true } else { false }
    }

    private func save() {
        let input = UnpaidWorkInput(start: TimeOfDay(pickerDate: start), end: TimeOfDay(pickerDate: end))
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

/// 改某个月的月薪 (PRD 4.2.1 #2、4.6.1)：只影响该月。校验与提示与设置页同一套 (`Validation.monthlySalary`)。
struct SalaryFormView: View {
    let month: YearMonth
    /// 如「2026年1月」。
    let title: String
    let actions: PanelActions
    let dismiss: () -> Void

    @State private var text: String
    @State private var errorMessage: String?

    init(month: YearMonth, title: String, current: Decimal, actions: PanelActions, dismiss: @escaping () -> Void) {
        self.month = month
        self.title = title
        self.actions = actions
        self.dismiss = dismiss
        _text = State(initialValue: NSDecimalNumber(decimal: current).stringValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(title)的月薪").font(.title3.bold())
            Text("只改这个月，其他月份不受影响").font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("月薪", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Text("元").foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            HStack {
                Button("取消", action: dismiss).keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 280)
        .onChange(of: text) { errorMessage = nil }
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
