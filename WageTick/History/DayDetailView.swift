import OSLog
import SwiftUI
import WageCore

/// 单日详情 (PRD 4.6.1、F11)：判定来源、结算、扣款明细、请假、白干段，以及编辑入口 (#15)。
/// 哪些入口可用、不可用的原因、表单预填都取自快照的 `DayEditing`，这里只管排版和发命令。
struct DayDetailView: View {
    let day: HistoryDay
    let actions: PanelActions

    @State private var deductionForm: DeductionFormRequest?
    @State private var leaveForm: LeaveFormView.Mode?
    @State private var unpaidWorkForm: UnpaidWorkFormView.Request?
    /// 直接发出的命令 (删除、单日覆盖) 被拒绝时的提示。
    @State private var errorMessage: String?

    private var detail: HistoryDayDetail { day.detail }
    private var editing: DayEditing { day.detail.editing }
    private var target: FormTarget { .day(day.date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let notice = detail.notice {
                Text(notice).font(.callout).foregroundStyle(.orange)
            }
            if !detail.stats.isEmpty {
                HistoryStatsGrid(stats: detail.stats)
            }
            ForEach(detail.deductions) { item in
                deductionRow(item)
            }
            leaveRow
            ForEach(editing.unpaidWorkItems) { item in
                unpaidWorkRow(item)
            }
            if let summary = detail.unpaidWorkSummary {
                Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            editButtons
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
        }
        .sheet(item: $deductionForm) { request in
            DeductionFormView(
                request: request, entry: editing.deduction.content, actions: actions, target: target,
                dismiss: { deductionForm = nil }
            )
        }
        .sheet(item: $unpaidWorkForm) { request in
            UnpaidWorkFormView(request: request, date: day.date, actions: actions, dismiss: { unpaidWorkForm = nil })
        }
    }

    private var header: some View {
        HStack {
            Text(detail.title).font(.headline)
            Text(day.kind.label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(day.kind.color, in: Capsule())
            Spacer()
            Text("\(detail.sourceItem.title) \(detail.sourceItem.value)").font(.callout).foregroundStyle(.secondary)
        }
    }

    /// 一笔扣钱：能记扣钱的日子可改可删；变成不上班日的那天只能删 (#14 遗留)。
    private func deductionRow(_ item: DeductionItem) -> some View {
        HistoryLineRow(title: item.title, detail: item.detail, value: item.amount) {
            if editing.deduction.isAvailable {
                Button { deductionForm = .edit(item) } label: { Image(systemName: "pencil") }.help("编辑")
            }
            Button { send(.editDay(day.date, .deleteDeduction(id: item.id))) } label: { Image(systemName: "trash") }
                .help("删除")
        }
    }

    /// 请假：能请假的日子点「修改」进表单 (撤销在表单里)；变成不上班日的那天只能直接撤销。
    @ViewBuilder
    private var leaveRow: some View {
        if let leave = detail.leave {
            HistoryLineRow(title: leave.title, detail: leave.detail, value: leave.value) {
                if let current = editing.leave.content?.current {
                    Button("修改") { leaveForm = .edit(current) }
                } else {
                    Button("撤销") { send(.editDay(day.date, .cancelLeave)) }
                }
            }
        }
    }

    private func unpaidWorkRow(_ item: UnpaidWorkItem) -> some View {
        HistoryLineRow(title: item.line.title, detail: item.line.detail, value: item.line.value) {
            if let input = item.input {
                Button { unpaidWorkForm = .edit(index: item.index, input) } label: { Image(systemName: "pencil") }.help("编辑")
            }
            Button { send(.editDay(day.date, .deleteUnpaidWork(index: item.index))) } label: { Image(systemName: "trash") }
                .help("删除")
        }
    }

    /// 编辑入口：记扣钱、请假、补记白干、单日覆盖。不可用的置灰，下方列出原因 (PRD 4.3.5 #8)。
    private var editButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("记扣钱") { deductionForm = .add }
                    .disabled(!editing.deduction.isAvailable)
                Button("请假") { leaveForm = .request }
                    .disabled(editing.leave.content?.canRequest != true)
                Button("补记白干") {
                    if let draft = editing.unpaidWork.content { unpaidWorkForm = .add(draft) }
                }
                .disabled(!editing.unpaidWork.isAvailable)
                Spacer()
                Button(editing.overrideButton.title) { send(editing.overrideButton.command) }
            }
            ForEach(reasons, id: \.self) { reason in
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        // 与扣钱表单分开挂，避免同一视图上挂两个以上 sheet 互相干扰。
        .sheet(item: $leaveForm) { mode in
            LeaveFormView(mode: mode, actions: actions, target: target, dismiss: { leaveForm = nil })
        }
    }

    /// 不可用入口的原因，去重后按出现顺序。
    private var reasons: [String] {
        let all = [editing.deduction.reason, editing.leave.reason, editing.unpaidWork.reason].compactMap { $0 }
        return all.enumerated().filter { all.firstIndex(of: $0.element) == $0.offset }.map(\.element)
    }

    private func send(_ command: Command) {
        do {
            try actions.send(command)
            errorMessage = nil
        } catch {
            errorMessage = error.message
            Self.logger.error("历史编辑失败：\(error.message, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: AppIdentity.bundleID, category: "History")
}

/// 详情里的一行：左边标题与说明，右边数值，再右边是操作按钮。
private struct HistoryLineRow<Actions: View>: View {
    let title: String
    let detail: String?
    let value: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).monospacedDigit()
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value).monospacedDigit()
            actions()
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}
