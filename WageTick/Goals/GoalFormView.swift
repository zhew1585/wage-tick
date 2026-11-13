import SwiftUI
import WageCore

/// 新建目标，或编辑排队中、累计中目标的名称和金额 (PRD 4.5.2，大胆版设计稿「弹窗-新目标」)，在目标窗口里原地打开，返回胶囊回到攒钱队列。
/// 橙色头图：标题「又想要啥了」(编辑时「编辑目标」)、头图里大号金额输入 (黄色光标)、「加到队尾，排第 N 个」(编辑时「现在排第 N 个」)、握拳小牛。
/// 下面只有名称输入框 (带字数) 与一行说明；底部「算了」+「加进队列」(编辑时「保存」)。
/// 编辑时初始值取自快照攒钱队列里的那一行 (`QueueGoalRow`)；校验交给核心，失败时展示 `CommandError.message`。
/// 改小金额导致已达标时核心会立即完成并激活下一个，这里不做判断。
struct GoalFormView: View {
    enum Mode: Identifiable, Equatable {
        case create
        case edit(QueueGoalRow)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let row): "edit-\(row.id)"
            }
        }
    }

    private enum Focus {
        case amount, name
    }

    let mode: Mode
    /// 在攒钱队列里排第几 (从 1 起)：新建是队尾，编辑是眼下的位置。
    let position: Int
    /// 保存：发 `.createGoal` 或 `.editGoal`，校验失败时抛出。
    let save: (Command) throws(CommandError) -> Void
    let dismiss: () -> Void

    @State private var name: String
    @State private var amountText: String
    @State private var errorMessage: String?
    @FocusState private var focus: Focus?

    init(mode: Mode, position: Int, save: @escaping (Command) throws(CommandError) -> Void, dismiss: @escaping () -> Void) {
        self.mode = mode
        self.position = position
        self.save = save
        self.dismiss = dismiss
        let row: QueueGoalRow? = if case .edit(let row) = mode { row } else { nil }
        _name = State(initialValue: row?.name ?? "")
        _amountText = State(initialValue: row?.amountInput ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            fields
            Spacer(minLength: 0)
            footer
        }
        .onChange(of: name) { errorMessage = nil }
        .onChange(of: amountText) { errorMessage = nil }
        .onAppear { focus = isEditing ? .name : .amount }
            }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var hero: some View {
        BoldHero(
            theme: .orange,
            back: HeroBack(label: "返回", action: dismiss),
            kicker: isEditing ? "编辑目标" : "又想要啥了",
            caption: isEditing ? "现在排第 \(position) 个" : "加到队尾，排第 \(position) 个",
            captionIcon: .hourglassSimple,
            cow: .pose(.excited),
            bubble: HeroBubbleContent(value: "冲！", numeric: false)
        ) {
            amountInput
        }
    }

    /// 头图里的金额：墨色 ¥ + 白色大号数字，没填时是半透明的「0」。
    private var amountInput: some View {
        HStack(alignment: .lastTextBaseline, spacing: Spacing.s4) {
            Text("¥").font(AppFont.heavy(34)).foregroundStyle(Palette.ink)
            TextField("金额", text: $amountText, prompt: Text(""))
                .textFieldStyle(.plain)
                // 光标白色：SwiftUI 刷新时会按 tint 重设光标颜色，只改字段编辑器会被盖掉。
                .tint(.white)
                .font(AppFont.heavy(64))
                .foregroundStyle(.white)
                .background(alignment: .leading) {
                    // 系统占位文字的颜色改不了 (在橙色底上发灰)，自己画一个半透明白的「0」。
                    if amountText.isEmpty {
                        Text("0").font(AppFont.heavy(64)).foregroundStyle(.white.opacity(0.4)).allowsHitTesting(false)
                    }
                }
                .focused($focus, equals: .amount)
                .onSubmit(submit)
                .accessibilityLabel("金额")
        }
        .frame(width: 210, alignment: .leading)
    }

    /// 名称输入框 (高 50、圆角 14、2pt 墨色描边、surface 底，右边字数) 与一行说明；校验失败的提示接在说明下面。
    private var fields: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.r14)
        return VStack(alignment: .leading, spacing: Spacing.s8) {
            Text("想要啥").font(AppFont.ui(12, .bold)).foregroundStyle(Palette.ink)
            HStack(spacing: Spacing.s8) {
                TextField("名称", text: $name, prompt: Text("如 Switch 2").foregroundStyle(Palette.muted))
                    .textFieldStyle(.plain)
                    .font(AppFont.ui(15, .semibold))
                    .foregroundStyle(Palette.ink)
                    .focused($focus, equals: .name)
                    .onSubmit(submit)
                Text("\(name.count)/\(Validation.goalNameLimit)")
                    .font(AppFont.num(11))
                    .foregroundStyle(name.count > Validation.goalNameLimit ? Palette.loss : Palette.muted)
            }
            .padding(.horizontal, Spacing.s14)
            .frame(height: 50)
            .background(Palette.surface, in: shape)
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: 2))
            .padding(.bottom, Spacing.s8)
            Text("之后可以改名字和金额。改小了刚好攒够的话，会直接算达成，换下一个。")
                .font(AppFont.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                Text(errorMessage).font(AppFont.caption).foregroundStyle(Palette.loss)
            }
        }
        .padding(EdgeInsets(top: Spacing.s24, leading: Spacing.screen, bottom: 0, trailing: Spacing.screen))
    }

    private var footer: some View {
        HStack(spacing: Spacing.s10) {
            Button("算了", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.pill(.outline))
                .frame(width: 108)
            Button(action: submit) {
                Label { Text(isEditing ? "保存" : "加进队列") } icon: { PhosphorIcon(isEditing ? .check : .plus) }
            }
            .buttonStyle(.pill(.ink))
        }
        .padding(EdgeInsets(top: Spacing.s12, leading: Spacing.screen, bottom: Spacing.screen, trailing: Spacing.screen))
    }

    private func submit() {
        let amount = AmountText.parse(amountText) ?? 0
        let command: Command = switch mode {
        case .create: .createGoal(name: name, amount: amount)
        case .edit(let row): .editGoal(id: row.id, name: name, amount: amount)
        }
        do {
            try save(command)
            dismiss()
        } catch {
            errorMessage = error.message
        }
    }
}
