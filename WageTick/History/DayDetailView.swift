import OSLog
import SwiftUI
import WageCore

/// 单日详情 (PRD 4.6.1、F11，设计稿 P5 单日详情 · 760)：页头日期与判定来源，当天结算 (大号数字与算式)，
/// 扣钱、请假、白干三段与「这天上不上班」，各段上沿一条分隔线。
/// 哪些入口可用、不可用的原因、表单预填都取自快照的 `DayEditing`，这里只管排版和发命令 (#15)。
/// 扣钱、白干的一行点一下修改，悬停时出现删除；不可用的入口不显示，改为在该段下面列出原因 (PRD 4.3.5 #8)。
struct DayDetailView: View {
    let day: HistoryDay
    let actions: PanelActions
    let back: () -> Void

    @State private var deductionForm: DeductionFormRequest?
    @State private var leaveForm: LeaveFormView.Mode?
    @State private var unpaidWorkForm: UnpaidWorkFormView.Request?
    /// 直接发出的命令 (删除、撤销、单日覆盖) 被拒绝时的提示。
    @State private var errorMessage: String?

    private var detail: HistoryDayDetail { day.detail }
    private var editing: DayEditing { day.detail.editing }
    private var target: FormTarget { .day(day.date) }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(detail.title, back: back) { sourceChip }
            ScrollBody {
                VStack(spacing: 0) {
                    if let notice = detail.notice {
                        Text(notice)
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.screen)
                            .padding(.vertical, Spacing.s10)
                            .background(Palette.accentSoft)
                    }
                    if let settled = detail.stats.first {
                        settlement(settled, rest: Array(detail.stats.dropFirst()))
                    }
                    deductionSection
                    leaveSection
                    unpaidWorkSection
                    overrideSection
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.loss)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.screen)
                            .padding(.bottom, Spacing.s14)
                    }
                }
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

    /// 页头右边的判定来源，如「判定来源：法定节假日」。
    private var sourceChip: some View {
        Text("\(detail.sourceItem.title)：\(detail.sourceItem.value)")
            .font(AppFont.ui(10, .medium))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s3)
            .background(Palette.surface, in: Capsule())
    }

    /// 当天结算：第一项大号展示 (当天结算、今日已赚或预计结算)，下面一行是其余项 (今日上限) 与算式 (「日薪 1000 − 扣款 50」)。
    private func settlement(_ settled: StatItem, rest: [StatItem]) -> some View {
        let notes = rest.map { "\($0.title) \($0.value)" } + [detail.breakdown].compactMap { $0 }
        return VStack(alignment: .leading, spacing: Spacing.s6) {
            Text(settled.title).font(AppFont.body).foregroundStyle(Palette.muted)
            Text(settled.value)
                .font(AppFont.num(44, .bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !notes.isEmpty {
                Text(notes.joined(separator: " · ")).font(AppFont.numCaption).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.s26)
        .padding(.bottom, Spacing.s24)
    }

    // MARK: 扣钱

    /// 扣钱：能记扣钱的日子可补记、可改；变成不上班日的那天已有的只能删 (#14 遗留)。
    private var deductionSection: some View {
        let available = editing.deduction.isAvailable
        return DetailSection(
            "扣钱", icon: .trendDown,
            add: available ? DetailSection.Add(title: "补记一笔") { deductionForm = .add } : nil
        ) {
            ForEach(detail.deductions) { item in
                DetailLine(
                    title: item.title, detail: item.detail, value: item.amount, tone: .loss,
                    edit: available ? { deductionForm = .edit(item) } : nil,
                    delete: { send(.editDay(day.date, .deleteDeduction(id: item.id))) }
                )
            }
            if detail.deductions.isEmpty {
                EmptyLine(editing.deduction.reason ?? "没扣钱")
            }
        }
    }

    // MARK: 请假

    /// 请假：能请假的日子点那一行进表单修改 (撤销在表单里)；变成不上班日的那天只能直接撤销。
    private var leaveSection: some View {
        let form = editing.leave.content
        return DetailSection(
            "请假", icon: .umbrella,
            add: form?.canRequest == true ? DetailSection.Add(title: "请假") { leaveForm = .request } : nil
        ) {
            if let leave = detail.leave {
                if let current = form?.current {
                    DetailLine(
                        title: leave.title, detail: leave.detail, value: leave.value, tone: .accent,
                        edit: { leaveForm = .edit(current) }, delete: nil
                    )
                } else {
                    DetailLine(
                        title: leave.title, detail: leave.detail, value: leave.value, tone: .accent,
                        edit: nil, delete: { send(.editDay(day.date, .cancelLeave)) }
                    )
                }
            } else {
                EmptyLine(editing.leave.reason ?? "没请假")
            }
        }
        // 与扣钱表单分开挂，避免同一视图上挂两个以上 sheet 互相干扰。
        .sheet(item: $leaveForm) { mode in
            LeaveFormView(mode: mode, actions: actions, target: target, dismiss: { leaveForm = nil })
        }
    }

    // MARK: 白干

    /// 白干：每段一行，右边是这一段倒贴的钱。
    private var unpaidWorkSection: some View {
        DetailSection(
            "白干", icon: .drop,
            add: editing.unpaidWork.content.map { draft in DetailSection.Add(title: "补记一段") { unpaidWorkForm = .add(draft) } }
        ) {
            ForEach(editing.unpaidWorkItems) { item in
                UnpaidWorkLine(
                    item: item,
                    edit: item.input.map { input in { unpaidWorkForm = .edit(index: item.index, input) } },
                    delete: { send(.editDay(day.date, .deleteUnpaidWork(index: item.index))) }
                )
            }
            if editing.unpaidWorkItems.isEmpty {
                EmptyLine(editing.unpaidWork.reason ?? "没白干")
            }
        }
    }

    // MARK: 单日覆盖

    private var overrideSection: some View {
        let choices = OverrideChoices(editing: editing)
        return DetailSection("这天上不上班", icon: .swap, add: nil) {
            ThemeSegmented(
                options: OverrideChoices.Choice.allCases.map { choice in
                    .init(id: choice, title: choice.title, isEnabled: choices.command(for: choice) != nil)
                },
                selection: choices.selected,
                size: .large
            ) { choice in
                if let command = choices.command(for: choice) { send(command) }
            }
            Text("改了会影响本月应出勤天数，整月日薪跟着重算。").font(AppFont.caption).foregroundStyle(Palette.muted)
        }
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

/// 「这天上不上班」三段：按规则、改成上班、改成不上班。
/// 核心只给一个按钮 (`DayEditing.overrideButton`)：没有覆盖时改成与规则相反的一种，有覆盖时撤销。
/// 这里按它的命令认出当前是哪一段、能点哪一段：能点的那段发这条命令，与当前判定相同的那段点不动。
private struct OverrideChoices {
    enum Choice: CaseIterable, Hashable {
        case rule, attendanceDay, dayOff

        var title: String {
            switch self {
            case .rule: "按规则"
            case .attendanceDay: "改成上班"
            case .dayOff: "改成不上班"
            }
        }
    }

    let selected: Choice
    /// 能点的那段与它发的命令。
    private let actionable: (choice: Choice, command: Command)?

    init(editing: DayEditing) {
        let command = editing.overrideButton.command
        guard case .editDay(_, let edit) = command else {
            (selected, actionable) = (.rule, nil)
            return
        }
        switch edit {
        case .setOverride(.attendanceDay): (selected, actionable) = (.rule, (.attendanceDay, command))
        case .setOverride(.dayOff): (selected, actionable) = (.rule, (.dayOff, command))
        // 已有覆盖：能请假说明这天现在要上班 (覆盖成上班日)，否则覆盖成不上班日。
        case .clearOverride: (selected, actionable) = (editing.leave.isAvailable ? .attendanceDay : .dayOff, (.rule, command))
        default: (selected, actionable) = (.rule, nil)
        }
    }

    func command(for choice: Choice) -> Command? {
        actionable?.choice == choice ? actionable?.command : nil
    }
}

/// 详情里的一段：小标题 (16 号图标 + 14/600 标题)，右边 accent 色「+ 补记」入口 (13/500)，下面是内容；上沿一条分隔线。
private struct DetailSection<Content: View>: View {
    struct Add {
        let title: String
        let action: () -> Void
    }

    let title: String
    let icon: Phosphor
    let add: Add?
    @ViewBuilder let content: () -> Content

    init(_ title: String, icon: Phosphor, add: Add?, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.add = add
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            HStack(spacing: Spacing.s6) {
                PhosphorIcon(icon, size: 16).foregroundStyle(Palette.muted)
                Text(title).font(AppFont.ui(14, .semibold)).foregroundStyle(Palette.ink)
                Spacer(minLength: Spacing.s8)
                if let add {
                    Button(action: add.action) {
                        HStack(spacing: Spacing.s4) {
                            PhosphorIcon(.plus, size: 12)
                            Text(add.title).font(AppFont.bodyMedium)
                        }
                        .foregroundStyle(Palette.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.highlight(radius: Radius.r6, outset: Spacing.s4))
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screen)
        .padding(.vertical, Spacing.s18)
        .overlay(alignment: .top) { CardDivider() }
    }
}

/// 段里没有记录时的一行 muted 说明，如「没请假」或入口不可用的原因。
private struct EmptyLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text).font(AppFont.body).foregroundStyle(Palette.muted)
    }
}

/// 扣钱、请假的一行 (圆角 10 色底)：标题 13/600、说明 13 muted，右边 13/600 等宽数值；点一下修改，悬停时出现删除。
private struct DetailLine: View {
    enum Tone {
        case loss, accent
    }

    let title: String
    let detail: String?
    let value: String
    let tone: Tone
    let edit: (() -> Void)?
    let delete: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Text(title).font(AppFont.bodySemibold).foregroundStyle(Palette.ink)
            if let detail {
                Text(detail).font(AppFont.body).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: Spacing.s8)
            if hovering, let delete {
                IconButton(systemName: edit == nil ? "arrow.uturn.backward" : "trash", help: edit == nil ? "撤销" : "删除", action: delete)
            }
            Text(value).font(AppFont.num(13, .semibold)).foregroundStyle(tone == .loss ? Palette.loss : Palette.accent)
        }
        .padding(.horizontal, Spacing.s14)
        .padding(.vertical, Spacing.s12)
        .background(tone == .loss ? Palette.lossSoft : Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.r10))
        .contentShape(Rectangle())
        .onTapGesture { edit?() }
        .hoverFeedback(cornerRadius: Radius.r10, isEnabled: edit != nil)
        .onHover { hovering = $0 }
        .help(edit == nil ? "" : "点一下修改")
    }
}

/// 白干的一行 (surface 底，圆角 10)：时段 13/600 等宽，后面时长 muted、疑似通宵或计时中 accent，右边这一段倒贴 (loss)；
/// 点一下修改，悬停时出现删除。
private struct UnpaidWorkLine: View {
    let item: UnpaidWorkItem
    let edit: (() -> Void)?
    let delete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Spacing.s8) {
            Text(item.line.title).font(AppFont.num(13, .semibold)).foregroundStyle(Palette.ink)
            Text(item.line.value).font(AppFont.body).foregroundStyle(Palette.muted)
            if let flag = item.line.detail {
                Text(flag).font(AppFont.small).foregroundStyle(Palette.accent)
            }
            Spacer(minLength: Spacing.s8)
            if hovering {
                IconButton(systemName: "trash", help: "删除", action: delete)
            }
            Text(item.loss).font(AppFont.num(13)).foregroundStyle(Palette.loss).lineLimit(1)
        }
        .padding(.horizontal, Spacing.s14)
        .padding(.vertical, Spacing.s12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.r10))
        .contentShape(Rectangle())
        .onTapGesture { edit?() }
        .hoverFeedback(cornerRadius: Radius.r10, isEnabled: edit != nil)
        .onHover { hovering = $0 }
    }
}
