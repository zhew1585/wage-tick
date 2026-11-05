import SwiftUI
import WageCore

/// 请假表单 (PRD F6)，从今日概览面板弹出：时段、扣日薪的百分比，下方汇总当日计划、请假扣薪、今日上限。
/// 汇总与校验提示都来自核心：每次改动都把待保存的命令交给 `AppModel.preview` 试算。
struct LeaveFormView: View {
    /// 新请一条 (与已有的另一半天假合并) 还是修改已有的那条 (整条替换)。
    enum Mode: Equatable {
        case request
        case edit(Leave)
    }

    let model: AppModel
    let mode: Mode
    /// 保存或撤销成功后回调，由面板关闭表单并刷新。
    let onSaved: () -> Void
    let onCancel: () -> Void

    @State private var period: LeavePeriod
    @State private var percentText: String
    @State private var errorMessage: String?

    init(model: AppModel, mode: Mode, onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.model = model
        self.mode = mode
        self.onSaved = onSaved
        self.onCancel = onCancel
        let initial = switch mode {
        case .request: Leave(period: .fullDay, deductionPercent: LeavePeriod.fullDay.defaultDeductionPercent)
        case .edit(let leave): leave
        }
        _period = State(initialValue: initial.period)
        _percentText = State(initialValue: Self.text(initial.deductionPercent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(mode == .request ? "请假" : "修改请假").font(.title3.bold())
            Picker("时段", selection: $period) {
                ForEach(LeavePeriod.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // 切换时段时带出默认比例【D4】，牛马可再修改。
            .onChange(of: period) { _, newValue in
                percentText = Self.text(newValue.defaultDeductionPercent)
            }
            HStack {
                Text("扣日薪")
                TextField("", text: $percentText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                Text("%")
            }
            summary
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            buttons
        }
        .padding(20)
        .frame(width: 320)
    }

    @ViewBuilder
    private var summary: some View {
        switch previewResult {
        case .success(let form):
            VStack(spacing: 6) {
                ForEach(form.summary, id: \.title) { item in
                    HStack {
                        Text(item.title).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.value).monospacedDigit()
                    }
                }
            }
            .font(.callout)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .failure(let error):
            Text(error.message).foregroundStyle(.red)
        }
    }

    private var buttons: some View {
        HStack {
            if case .edit = mode {
                Button("撤销请假", role: .destructive) { send(.cancelLeave) }
            }
            Spacer()
            Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
            Button("保存") { save() }.keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        guard let command = pendingCommand else {
            errorMessage = Validation.leaveDeductionPercent(nil)?.message
            return
        }
        send(command)
    }

    private func send(_ command: Command) {
        do {
            try model.send(command)
            onSaved()
        } catch {
            errorMessage = error.message
        }
    }

    /// 待保存的命令；比例没填或不是数字时为 nil。
    private var pendingCommand: Command? {
        guard let percent = parsedPercent else { return nil }
        let leave = Leave(period: period, deductionPercent: percent)
        return mode == .request ? .requestLeave(leave) : .editLeave(leave)
    }

    /// 试算结果：比例填错时给出核心的校验提示。
    private var previewResult: Result<LeaveForm, CommandError> {
        guard let command = pendingCommand else { return .failure(.leavePercentOutOfRange) }
        return model.preview(command).flatMap { snap in
            snap.leaveForm.map { .success($0) } ?? .failure(.notAttendanceDay)
        }
    }

    /// 只认纯数字写法 (可带小数)，其他写法视为未填；范围交给核心的 `Validation`。
    private var parsedPercent: Decimal? {
        let text = percentText.trimmingCharacters(in: .whitespaces)
        guard text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    /// 比例填进输入框的写法，如 `100`、`12.5`。
    private static func text(_ percent: Decimal) -> String {
        NSDecimalNumber(decimal: percent).stringValue
    }
}

extension LeaveFormView.Mode: Identifiable {
    /// 供 `.sheet(item:)` 区分新请与修改。
    var id: String {
        switch self {
        case .request: "request"
        case .edit: "edit"
        }
    }
}
