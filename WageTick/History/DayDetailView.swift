import OSLog
import SwiftUI
import WageCore

/// 单日详情 (PRD 4.6.1、F11，设计稿「历史-单日详情」)：墨色头图写日期与当天结算 (大数字与算式)，有扣钱那天小牛大哭；
/// 下面扣钱、请假、白干、这天上不上班四块，每块右上角橙色「+ 补记…」，记录是描边圆角卡。
/// 哪些入口可用、不可用的原因、表单预填都取自快照的 `DayEditing`，这里只管排版和发命令 (#15)。
/// 扣钱、白干的卡点一下修改，悬停时出现删除；不可用的入口不显示，改为在该块里写出原因 (PRD 4.3.5 #8)。
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
        HeroScroll { collapse in
            hero(collapse)
        } content: {
            VStack(alignment: .leading, spacing: Spacing.s22) {
                if let notice = detail.notice {
                    PanelNoticeBanner(text: notice)
                }
                deductionSection
                leaveSection
                unpaidWorkSection
                overrideSection
                if let errorMessage {
                    Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, Spacing.s18)
            .padding(.bottom, Spacing.s24)
        }
        .sheet(item: $deductionForm) { request in
            DeductionFormView(
                request: request, entry: editing.deduction.content, actions: actions, target: target,
                dismiss: { deductionForm = nil }
            )
        }
        .sheet(item: $unpaidWorkForm) { request in
            UnpaidWorkFormView(
                request: request, date: day.date, endDays: editing.unpaidWorkEndDays, actions: actions, dismiss: { unpaidWorkForm = nil }
            )
        }
    }

    // MARK: 头图

    /// 头图：标题「11月4日 周三 · 当天结算」，大数字是第一项结算 (当天结算、今日已赚或预计结算)，
    /// 说明行是其余项 (今日上限) 与算式 (「日薪 1000 − 扣款 50」)，都没有时写判定来源。
    /// 不应出勤的日子没有结算：标题写「休息日」或「改成不上班」，大数字 ¥0。
    private func hero(_ collapse: CGFloat) -> some View {
        let settled = detail.stats.first
        let notes = detail.stats.dropFirst().map { "\($0.title) \($0.value)" } + [detail.breakdown].compactMap { $0 }
        let source = "\(detail.sourceItem.title)：\(detail.sourceItem.value)"
        let number = settled?.value ?? "¥0"
        return BoldHero(
            theme: .ledger,
            back: HeroBack(label: monthLabel, action: back),
            kicker: "\(detail.title) · \(settled?.title ?? day.kind.label)",
            caption: notes.isEmpty ? source : notes.joined(separator: " · "),
            captionIcon: .coins,
            cow: cow.act,
            bubble: HeroBubbleContent(value: cow.line, numeric: false),
            collapse: collapse,
            compactValue: heroCompactMoney(number)
        ) {
            HeroAmount(text: number, theme: .ledger, size: 96, maxWidth: 220)
        }
    }

    /// 返回胶囊写这一天所在的月份，如「11月」。
    private var monthLabel: String { "\(day.date.month)月" }

    /// 小牛：有扣钱那天大哭、说被扣了多少；不上班的日子晒太阳；其余端着咖啡。
    private var cow: (act: CowAct, line: String) {
        if let deducted = detail.deducted { return (.crying, "被扣了 \(deducted)") }
        if detail.stats.isEmpty { return (.pose(.sunbathing), "歇着呢") }
        return (.pose(.working), "都记着呢")
    }

    // MARK: 扣钱

    /// 扣钱：能记扣钱的日子可补记、可改；变成不上班日的那天已有的只能删 (#14 遗留)。
    private var deductionSection: some View {
        let available = editing.deduction.isAvailable
        return HistorySection(
            "扣钱",
            add: available ? HistorySection.Add(title: "补记一笔") { deductionForm = .add } : nil
        ) {
            ForEach(detail.deductions) { item in
                RecordCard(
                    title: item.title, detail: item.detail, value: item.amount, valueColor: Palette.loss,
                    edit: available ? { deductionForm = .edit(item) } : nil,
                    delete: { send(.editDay(day.date, .deleteDeduction(id: item.id))) }
                )
            }
            if detail.deductions.isEmpty {
                EmptyRecord(editing.deduction.reason ?? "没扣钱")
            }
        }
    }

    // MARK: 请假

    /// 请假：能请假的日子点那张卡进表单修改 (撤销在表单里)；变成不上班日的那天只能直接撤销。
    private var leaveSection: some View {
        let form = editing.leave.content
        return HistorySection(
            "请假",
            add: form?.canRequest == true ? HistorySection.Add(title: "请假") { leaveForm = .request } : nil
        ) {
            if let leave = detail.leave {
                if let current = form?.current {
                    RecordCard(
                        title: leave.title, detail: leave.detail, value: leave.value, valueColor: Palette.loss,
                        edit: { leaveForm = .edit(current) }, delete: nil
                    )
                } else {
                    RecordCard(
                        title: leave.title, detail: leave.detail, value: leave.value, valueColor: Palette.loss, deleteHelp: "撤销",
                        edit: nil, delete: { send(.editDay(day.date, .cancelLeave)) }
                    )
                }
            } else {
                EmptyRecord(editing.leave.reason ?? "没请假")
            }
        }
        // 与扣钱表单分开挂，避免同一视图上挂两个以上 sheet 互相干扰。
        .sheet(item: $leaveForm) { mode in
            if let form {
                LeaveFormView(mode: mode, form: form, actions: actions, target: target, dismiss: { leaveForm = nil })
            }
        }
    }

    // MARK: 白干

    /// 白干：每段一张卡，标题是时段，说明是倒贴的钱 (可能忘了停、计时中接在后面)，右边时长。
    private var unpaidWorkSection: some View {
        HistorySection(
            "白干",
            add: editing.unpaidWork.content.map { draft in HistorySection.Add(title: "补记一段") { unpaidWorkForm = .add(draft) } }
        ) {
            ForEach(editing.unpaidWorkItems) { item in
                RecordCard(
                    title: item.line.title,
                    detail: ([item.loss] + [item.line.detail].compactMap { $0 }).joined(separator: " · "),
                    value: item.line.value,
                    monospacedTitle: true,
                    edit: item.input.map { input in { unpaidWorkForm = .edit(index: item.index, input) } },
                    delete: { send(.editDay(day.date, .deleteUnpaidWork(index: item.index))) }
                )
            }
            if editing.unpaidWorkItems.isEmpty {
                EmptyRecord(editing.unpaidWork.reason ?? "没白干")
            }
        }
    }

    // MARK: 单日覆盖

    /// 这天上不上班：按规则、改成上班、改成不上班三段，下面一行判定来源与改了会怎样。
    private var overrideSection: some View {
        let choices = OverrideChoices(editing: editing)
        return HistorySection("这天上不上班") {
            PillSegmented(
                options: OverrideChoices.Choice.allCases.map { choice in
                    .init(id: choice, title: choice.title, isEnabled: choices.command(for: choice) != nil)
                },
                selection: choices.selected
            ) { choice in
                if let command = choices.command(for: choice) { send(command) }
            }
            Text("\(detail.sourceItem.title)：\(detail.sourceItem.value)。\(editing.overrideNote)")
                .font(AppFont.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
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
