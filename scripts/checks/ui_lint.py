#!/usr/bin/env python3
"""界面与恢复边界的静态规则：只读源码，哪里都能跑 (不需要 Xcode)。

用法：python3 scripts/checks/ui_lint.py [--root <仓库根目录>]
退出码：0 通过；1 有规则不过；2 blocked (规则要看的文件不在，没法判断)。
每条规则对应这几轮真实踩过的坑，见 scripts/checks/README.md。规则看的是源码的写法，重构改了名字或结构时要同步改规则。
"""
import argparse, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))


class Blocked(Exception):
    pass


class Lint:
    def __init__(self, root):
        self.root = root
        self.failures = []
        self.cache = {}

    def read(self, rel):
        if rel not in self.cache:
            path = os.path.join(self.root, rel)
            if not os.path.isfile(path):
                raise Blocked(f'规则要看的文件不在：{rel}')
            self.cache[rel] = open(path, encoding='utf-8').read()
        return self.cache[rel]

    def swift_files(self, *dirs):
        for directory in dirs:
            for base, _, names in os.walk(os.path.join(self.root, directory)):
                for name in sorted(names):
                    if name.endswith('.swift'):
                        yield os.path.relpath(os.path.join(base, name), self.root)

    def fail(self, rule, where, text):
        self.failures.append(f'FAIL [{rule}] {where}: {text}')

    def forbid(self, rule, pattern, dirs, why):
        regex = re.compile(pattern)
        for rel in self.swift_files(*dirs):
            for number, line in enumerate(self.read(rel).splitlines(), 1):
                if regex.search(line):
                    self.fail(rule, f'{rel}:{number}', f'{why}：{line.strip()[:80]}')

    def require(self, rule, rel, pattern, why):
        if not re.search(pattern, self.read(rel), re.S):
            self.fail(rule, rel, why)

    def body(self, rel, signature):
        """取某个函数或计算属性的花括号内容。"""
        text = self.read(rel)
        start = text.find(signature)
        if start < 0:
            return None
        open_at = text.find('{', start)
        depth = 0
        for i in range(open_at, len(text)):
            depth += text[i] == '{'
            depth -= text[i] == '}'
            if depth == 0:
                return text[open_at:i + 1]
        return None


SHELL = ('WageTick', 'WageTickWidgets')


def restore_boundary(lint):
    """恢复边界：大胆版的组件、三个独立窗口、已到手页不能回来；核心的数据与计算不能删。"""
    lint.forbid(
        'RESTORE-BOLD',
        r'\b(HeroTheme|BoldHero|HeroAmount|HeroScroll|HeroNumberInput|PillButtonStyle|InkToggleStyle|BoldAlert|BoldConfirm|SegmentedText)\b'
        r'|\.pill\(|AppFont\.(heavy|fun|round)\b|Palette\.(highlight|hot|lime)\b',
        SHELL, '大胆版的组件、字体、颜色不该出现在外壳里 (老页面按原版还原，不是换皮)')
    fonts = os.path.join(lint.root, 'WageTick', 'Resources', 'Fonts')
    for name in sorted(os.listdir(fonts)) if os.path.isdir(fonts) else []:
        if re.match(r'(ArchivoBlack|ZCOOL)', name):
            lint.fail('RESTORE-BOLD', f'WageTick/Resources/Fonts/{name}', '大胆版的展示字体不该打包')
    lint.forbid('RESTORE-EARNED', r'GoalEarned|showsEarned|已到手', SHELL, '「已到手」页已按 Allen 的决定去掉，外壳里不该再有')
    lint.forbid('RESTORE-WINDOWS', r'\b(GoalsWindowController|HistoryWindowController|SettingsWindowController|PageWindow)\b', SHELL,
                '目标、历史、设置保留窗口内推入，不恢复三个独立窗口')
    cfg = json.load(open(os.path.join(HERE, 'ui-lint.json'), encoding='utf-8'))
    core = '\n'.join(lint.read(rel) for rel in lint.swift_files(os.path.join('WageCore', 'Sources')))
    if not core:
        raise Blocked('WageCore/Sources 里没有源码')
    for symbol in cfg['coreSymbols']:
        if not re.search(r'\b' + re.escape(symbol) + r'\b', core):
            lint.fail('CORE-KEPT', 'WageCore/Sources', f'核心里的 {symbol} 不见了：底层数据与计算不能随界面还原一起删')
    tests = sum(len(re.findall(r'@Test\b', lint.read(rel))) for rel in lint.swift_files(os.path.join('WageCore', 'Tests')))
    if tests < cfg['minCoreTests']:
        lint.fail('CORE-KEPT', 'WageCore/Tests', f"核心测试只有 {tests} 个 @Test，少于基线 {cfg['minCoreTests']}：测试不能跟着回退")
    lint.require('COPY-LEAVE', 'WageCore/Sources/WageCore/Snapshot/LeaveForm.swift', r'deductionText = "= \\\(Format\.money\(',
                 '请假表单比例框右侧的扣薪文字要按原版显示「= ¥1000」(Allen 2026-11-25 看过原版图后定)')


def page_header(lint):
    """页头：所有页面用同一个 PageHeader，都能返回；首页与下一级各用各的排法；标题栏方案不变。"""
    cfg = json.load(open(os.path.join(HERE, 'ui-lint.json'), encoding='utf-8'))
    seen = {}
    for rel in lint.swift_files('WageTick'):
        if rel.endswith('Components/PageHeader.swift'):
            continue
        for number, line in enumerate(lint.read(rel).splitlines(), 1):
            if line.lstrip().startswith('///') or 'PageHeader(' not in line:
                continue
            seen.setdefault(rel, []).append((number, line))
    for rel, calls in seen.items():
        role = cfg['pageHeaderCallers'].get(rel)
        if role is None:
            lint.fail('HDR-CALLER', rel, '新用了 PageHeader 的页面要在 scripts/checks/ui-lint.json 的 pageHeaderCallers 里登记是首页 (root) 还是下一级 (sub)，'
                      '并在 ui-geometry.json 里加上它的预览图，否则几何检查覆盖不到它')
            continue
        for number, line in calls:
            if 'back:' not in line:
                lint.fail('HDR-CALLER', f'{rel}:{number}', '推进来的页面的页头都要传 back (能返回)')
            if role == 'root' and 'isRoot: true' not in line:
                lint.fail('HDR-CALLER', f'{rel}:{number}', '页面首页 (目标、历史月列表、设置) 的页头要传 isRoot: true，三页排法才一致')
            if role == 'sub' and 'isRoot' in line:
                lint.fail('HDR-CALLER', f'{rel}:{number}', '下一级页面 (月日历、单日详情) 的页头保持原版排法，不传 isRoot')
    for rel, role in cfg['pageHeaderCallers'].items():
        if rel not in seen:
            lint.fail('HDR-CALLER', rel, f'登记为 {role} 的页面里没找到 PageHeader(…) 调用：页面换了页头就要同步改规则')
    controller = 'WageTick/Panel/TodayPanelWindowController.swift'
    lint.require('HDR-TITLEBAR', controller, r'makeWindow\(PanelWindow\.self,[^\n]*titlebar: \.tall',
                 '今日概览窗口要用 52 高的 .tall 标题栏 (页头与红绿灯同一行；Allen 2026-11-26 已接受)')
    # 首页各区域按 HomeLayout 从窗口顶边定位，所有状态下位置一致 (Allen 2026-11-26 定)；不再按内容高度叠、放不下就收紧。
    panel = 'WageTick/Panel/TodayPanelView.swift'
    lint.require('HOME-LAYOUT', panel, r'HomeLayout\.', '首页各区域要按 HomeLayout 的位置排 (各状态下位置一致)，不能按内容高度一段段叠起来')
    lint.require('HOME-LAYOUT', 'WageTick/Theme/Metrics.swift', r'static let size = CGSize\(width: 360, height: 574\)',
                 '窗口是 360×574 (首页七个区域叠起来正好)；要改尺寸得同步改 HomeLayout 与 scripts/checks/ui-home.json')
    lint.forbid('HOME-LAYOUT', r'\b(ViewThatFits|GoalDensity|titlebarInset)\b', ['WageTick/Panel'],
                '首页不再随内容伸缩：放不下就收紧、让出标题栏高度这些做法都已去掉')
    # 首页上哪些字要留、哪些已经去掉 (Allen 2026-11-26 逐项定的)。留的是信息，去掉的是解释性的前缀与小标题。
    sections = 'WageTick/Panel/PanelSections.swift'
    for pattern, what in ((r'Text\(label\)', '主数字上方的小标题 (今日已赚 / 今日结算 / 今日已倒贴)'),
                          (r'Text\(caption\)', '主数字下方的说明行 (日薪时薪、白干起止、扣款)'),
                          (r'Text\(progress\.label\)', '进度条上方的「已工作 x / y 小时」'),
                          (r'Text\(item\.title\)', '统计卡每格的小标题 (三格内容随状态变，只有图标看不懂)')):
        lint.require('HOME-COPY', sections, pattern, f'首页要保留{what}，Allen 明确要求留着')
    lint.require('HOME-COPY', panel, r'"今日结算" : "今日已赚"', '首页主数字上方的小标题要保留 (已下班「今日结算」，其余「今日已赚」)')
    home_files = (panel, sections, 'WageTick/Panel/GoalCardView.swift')
    removed = {r'\.startText\b|\.endText\b': '进度条两端只放时刻 (startClock / endClock)，不带「上班」「下班」',
               r'\.shortEstimate\b|\.estimate\b': '目标卡只放预计日期 (finishText)，不带「还需 N 天」「预计」',
               r'\.tagline\b|nextAttendanceText': '休息日只放下一个上班日的日期 (nextAttendanceDate)，不带说明句和前缀',
               r'goalCountText|"攒钱队列"': '攒钱队列没有小标题和「N 个目标」计数',
               r'\.currentText\b|Text\("修改"\)': '请假后的信息放在「请假」按钮的位置 (shortText 加 deductionRateText)，没有单独的一行和「修改」按钮',
               r'ScrollView|ScrollBody': '首页不滚动：攒钱队列最多显示 3 个目标，各区域位置固定'}
    for rel in home_files:
        for number, line in enumerate(lint.read(rel).splitlines(), 1):
            # 注释不算；悬停提示 (.help) 里放完整的一句不算，它不占画面。
            if line.strip().startswith('//') or '.help(' in line:
                continue
            for pattern, why in removed.items():
                if re.search(pattern, line):
                    lint.fail('HOME-COPY', f'{rel}:{number}', f'{why}：{line.strip()[:70]}')
    lint.require('HOME-COPY', 'WageTick/Panel/GoalCardView.swift', r'\.prefix\(2\)', '攒钱队列最多显示 3 个目标 (累计中 1 个加排队中前 2 个)，超过 3 个不加任何标记')
    if sum(lint.read(rel).count('Image(.cowMascot)') for rel in home_files) != 1:
        lint.fail('HOME-COPY', sections, '首页只有休息日那一块放小牛头像 (原版就有)，上班类状态不放小牛')
    lint.require('HOME-COPY', panel, r'panel\.notices \+ \[notice\]', '「扣款超过日薪」的提示放进顶部提示条，不在说明行下面另起一行')
    # 提示条只有文字 (Allen 2026-11-27 实机验收：前面的警告图标去掉)。
    banner = re.search(r'\nstruct PanelNoticeBanner\b.*?(?=\n(?:private |fileprivate )?(?:struct|enum|final class|class|extension) )', lint.read(sections), re.S)
    if banner is None:
        lint.fail('HOME-COPY', sections, '没找到 PanelNoticeBanner：提示条换了名字就要同步改这条规则')
    elif any('Icon(' in line or 'Image(' in line for line in banner.group(0).splitlines() if not line.strip().startswith('//')):
        lint.fail('HOME-COPY', sections, '首页提示条只有文字，不放图标 (Allen 2026-11-27 要求去掉前面的警告图标)')
    # 白干计时中 (Allen 2026-11-27 定)：进度区是白干进度条，「终于下班了」在情绪按钮区，这期间不放「今天扣钱了」。
    lint.require('HOME-UNPAID', panel, r'PanelProgress\(progress: unpaidWork\.progress, tone: Palette\.loss\)\.homeBand\(HomeLayout\.progress\)',
                 '白干计时中进度区要放白干进度条 (从开始走到自动停止时刻，loss 色)，不是黑按钮')
    lint.require('HOME-UNPAID', panel, r'case \.unpaidWork:\s*\n\s*if let button = panel\.unpaidWorkButton \{\s*\n\s*buttons\.append\(\.stopUnpaidWork\(button\)\)\s*\n\s*\}\s*\n\s*case ',
                 '白干计时中情绪按钮区左边只放「终于下班了」(不管是不是休息日)，这期间不放「今天扣钱了」')
    lint.require('HOME-UNPAID', 'WageCore/Sources/WageCore/Snapshot/TodayPanel.swift', r'"最多白干 ',
                 '白干进度条上方写「最多白干 N 小时」(到自动停止时刻为止)，文案在核心里')
    lint.require('HDR-FORM', 'WageTick/Panel/FormSheet.swift', r'PageHeader\(title, back: back, isRoot: true\)',
                 '扣钱、请假表单在窗口里的页头要用和目标页一样的 PageHeader (与红绿灯同一行，箭头 85、标题 100)')
    lint.require('HDR-FORM', panel, r'\.environment\(\\\.formSheetPlacement, \.window\)', '首页窗口里原地打开的表单要标成 .window，页头才会排到红绿灯那一行')
    lint.require('HDR-TITLEBAR', 'WageTick/Components/WindowChrome.swift', r'case \.tall: 52', '.tall 标题栏的高度是 52')
    lint.require('HDR-TITLEBAR', 'WageTick/Components/PageHeader.swift', r'height: CGFloat \{ WindowChrome\.Titlebar\.tall\.height \}',
                 '页头高度取 .tall 标题栏的高度，返回与标题才会和红绿灯在一条线上')
    previews = lint.body('WageTick/Shared/PagePreviews.swift', 'private static func page(')
    if previews is None:
        raise Blocked('PagePreviews.swift 里没找到 page(…)')
    if '.padding(.top' in previews:
        lint.fail('HDR-TITLEBAR', 'WageTick/Shared/PagePreviews.swift', '页面预览不能在上方另留一行：页头要顶到窗口上沿，否则预览和真窗口对不上')


def navigation(lint):
    """导航：盖页后底层停用、Esc 逐级、开着表单时不换页、点 Dock 不退页、目标卡可点、历史页退场状态。"""
    view = 'WageTick/Panel/TodayPanelView.swift'
    controller = 'WageTick/Panel/TodayPanelWindowController.swift'
    body = lint.body(view, 'var body: some View')
    if body is None:
        raise Blocked('TodayPanelView.swift 里没找到 body')
    for needle, why in [
        ('.disabled(content.page != nil)', '有页面盖着时底下的概览要停用 (点不到、聚焦不到)'),
        ('.accessibilityHidden(content.page != nil)', '有页面盖着时底下的概览要对辅助功能隐藏'),
        ('PinButton(', '钉住按钮要画在概览那一层，页面滑进滑出时才不会叠在页头右侧的内容上'),
    ]:
        if needle not in body:
            lint.fail('NAV-COVER', view, why)
    if 'PinButton(' in lint.read(controller):
        lint.fail('NAV-COVER', controller, '钉住按钮不能再由窗口控制器盖在最上层')
    cancel = lint.body(controller, 'private func handleCancel()')
    if cancel is None:
        lint.fail('NAV-ESC', controller, 'Esc 的兜底 handleCancel() 不见了')
    else:
        for needle, why in [
            ('goBackInside(page)', '页面里有下一级时 Esc 要先退那一级，不能直接跳回概览'),
            ('content.route != .home', '概览上开着扣钱、请假表单时 Esc 要回概览，不能关窗'),
        ]:
            if needle not in cancel:
                lint.fail('NAV-ESC', controller, why)
    lint.require('NAV-ESC', controller, r'panel\.onCancel = \{[^}]*handleCancel\(\)', '窗口的 Esc 要走 handleCancel()')
    lint.require('NAV-ESC', controller, r'if content\.leaveForm == nil, case \.leave = content\.route',
                 '请假表单开着时没了 (过零点) 路由要回到概览，否则第一次 Esc 白按')
    show = lint.body(controller, 'func show(replacing')
    if show is None:
        raise Blocked('TodayPanelWindowController.swift 里没找到 show(replacing:…)')
    if 'panel.attachedSheet != nil' not in show or not re.search(r'else if !hasSheet\s*\{\s*push\(page\)', show):
        lint.fail('NAV-SHEET', controller, '页面上开着弹出的表单时，⌘2 ⌘3 ⌘, 只前置不换页 (push 要受 hasSheet 保护)')
    if not re.search(r'else if isOpen, !hasSheet, returnsToOverview\s*\{\s*pop\(\)', show):
        lint.fail('NAV-SHEET', controller, '⌘1 回概览要同时满足：窗口开着、没有弹出的表单、调用方要求回概览')
    reopen = lint.body('WageTick/App/AppDelegate.swift', 'func applicationShouldHandleReopen')
    if reopen is None or 'todayPanel.show(returnsToOverview: false)' not in reopen:
        lint.fail('NAV-DOCK', 'WageTick/App/AppDelegate.swift', '点 Dock 图标只把窗口找回来，不能从页面退回概览')
    lint.require('NAV-GOALCARD', 'WageTick/Panel/GoalCardView.swift',
                 r'func tappable\([^)]*\)[^{]*\{\s*Button\(action: openGoals\)', '概览上的目标卡片要能点进目标页 (Allen 2026-11-26 定)')
    cards = lint.read('WageTick/Panel/GoalCardView.swift')
    for view in ('ActiveGoalCardView(', 'QueuedGoalTile('):
        if f'tappable {{ {view}' not in cards:
            lint.fail('NAV-GOALCARD', 'WageTick/Panel/GoalCardView.swift', f'没找到 tappable {{ {view}…) }}：目标卡的视图改了名或换了写法，这条规则要跟着改，不能因为找不到就算过')
        for match in re.finditer(re.escape(view), cards):
            before = cards[max(0, match.start() - 40):match.start()]
            if 'struct ' not in before and 'tappable {' not in before:
                lint.fail('NAV-GOALCARD', 'WageTick/Panel/GoalCardView.swift', f'{view}…) 要包在 tappable {{ }} 里，点了才进目标页')
    history = 'WageTick/History/HistoryPage.swift'
    disappear = lint.body(history, 'func disappear()')
    if disappear is None:
        raise Blocked('HistoryPage.swift 里没找到 disappear()')
    if re.search(r'content\.(snapshot|selectedMonth|selectedDay)\s*=\s*nil', disappear):
        lint.fail('NAV-HISTORY', history, '历史页退出去时不能清空快照与选中项：页面还在往右滑，内容会先消失')
    appear = lint.body(history, 'func appear()') or ''
    if 'content.selectedMonth = nil' not in appear:
        lint.fail('NAV-HISTORY', history, '历史页每次进来要回到月列表 (在 appear 里重置)')
    lint.require('NAV-HISTORY', history, r'func goBack\(\) -> Bool', '历史页要能自己退一级 (goBack)，Esc 才能逐级返回')
    for rel in (history, 'WageTick/Goals/GoalsPage.swift'):
        refresh = lint.body(rel, 'private func refresh()')
        if refresh is None or 'guard isActive else { return }' not in refresh:
            lint.fail('NAV-TIMER', rel, '页面退出去之后的刷新不能再排定时器 (refresh 里要先看 isActive)')


def fonts(lint):
    """字体：界面字体与数字字体只从 App 打包的字体文件建，不按字族名、字体名让系统挑 (机器上另装了同名字体时会被顶替)。"""
    lint.forbid(
        'FONT-BUNDLED',
        r'\.family\s*:|kCTFontFamilyNameAttribute|NSFontFamilyAttribute|NSFontDescriptor\.AttributeName\.family'
        r'|Font\.custom\(|\.custom\(\s*"|CTFontCreateWithName\(|NSFont\(name:|withFamily:|fontNamed',
        SHELL, '按字族名或字体名建字体，本机另装了同名字体时取到的是装的那份 (行高差很多)；要从打包的字体文件建 (AppFont)')
    rel = 'WageTick/Theme/AppFont.swift'
    lint.require('FONT-BUNDLED', rel, r'CTFontManagerCreateFontDescriptorsFromURL',
                 'AppFont 要从 App 包里的字体文件取字体描述 (CTFontManagerCreateFontDescriptorsFromURL)')
    make = lint.body(rel, 'private static func makeFont(')
    if make is None:
        lint.fail('FONT-BUNDLED', rel, '找不到 makeFont (改名了要同步改 ui_lint.py)')
    elif 'CTFontCreateWithFontDescriptor' not in make:
        lint.fail('FONT-BUNDLED', rel, 'makeFont 要用打包字体文件的描述建字体 (CTFontCreateWithFontDescriptor)，不能按名字取')


def goals(lint):
    """目标管理页：累计中一行不带「累计中」标签；名称放不下时悬停滚动；目标金额有上限、预计完成不逐天数到天荒地老。"""
    lint.forbid('GOALS-ROW', r'Text\("累计中"\)', ['WageTick/Goals'],
                '目标管理页累计中一行不带「累计中」标签 (Allen 2026-11-26 定)，标签会把名称挤得只剩两三个字')
    lint.forbid('GOALS-ROW', r'Text\((row|card)\.name\)', ['WageTick/Goals'],
                '目标管理页的目标名称要用 HoverMarqueeText：放不下时省略，悬停时滚动露出全文 (Allen 2026-11-26 定)')
    queue = 'WageTick/Goals/GoalQueueList.swift'
    for name in ('card.name', 'row.name'):
        lint.require('GOALS-ROW', queue, r'HoverMarqueeText\(' + re.escape(name) + r', isActive: showsButtons\)',
                     f'攒钱队列的行里没找到 HoverMarqueeText({name}, isActive: showsButtons)：名称换了写法，这条规则要跟着改，不能因为找不到就算过')
    lint.require('GOALS-ROW', 'WageTick/Goals/GoalsView.swift', r'HoverMarqueeText\(row\.name, isActive: hovering\)',
                 '已完成目标的行里没找到 HoverMarqueeText(row.name, isActive: hovering)：名称换了写法，这条规则要跟着改')
    # 三种行同一个三行结构 (Allen 2026-11-27 实机验收)：悬停出现的按钮在第三行最右，不挤名称；名称一栏悬停前后一样宽，滚动裁在整栏上。
    layout = 'WageTick/Goals/GoalRowLayout.swift'
    lint.require('GOALS-ROW', layout, r'HStack\(spacing: Spacing\.s8\) \{\s*\n\s*name\.frame\(minWidth: nameMinWidth, maxWidth: \.infinity, alignment: \.leading\)'
                                      r'\s*\n\s*amount\.lineLimit\(1\)\.layoutPriority\(1\)\s*\n\s*\}',
                 '目标行的第一行只能有名称和金额 (名称占满金额左边，间距 8)：按钮放进这一行，悬停时名称会被挤短 (Allen 2026-11-27 反馈)')
    lint.require('GOALS-ROW', layout, r'caption\.lineLimit\(1\)\.frame\(maxWidth: \.infinity, alignment: \.leading\)\s*\n\s*buttons\s*\n',
                 '目标行悬停时的编辑、删除按钮放在第三行最右 (小字的右边)')
    lint.require('GOALS-ROW', layout, r'static let height: CGFloat = 76\b', '目标页三种行的行高都是 76 (拖动排序按统一行高算落点)')
    for rel, count, what in ((queue, 2, '累计中、排队中'), ('WageTick/Goals/GoalsView.swift', 1, '已完成')):
        if len(re.findall(r'\bGoalRowLayout\(', lint.read(rel))) != count:
            lint.fail('GOALS-ROW', rel, f'{what}的行都要用 GoalRowLayout 这一个三行结构 (名称与金额、进度条、小字与按钮)，位置才对得齐；这里应有 {count} 处')
    lint.require('GOALS-ROW', 'WageTick/Components/HoverMarqueeText.swift',
                 r'\.frame\(maxWidth: \.infinity, alignment: \.leading\)\s*\n\s*\.background \{ widthReader \{ shownWidth = \$0 \} \}',
                 '名称滚动的可见区域要等于名称一栏的宽度 (先占满这一栏再量宽)：量在截断后的文字上，滚动时右边会空出一段 (Allen 2026-11-27 反馈)')
    lint.require('GOALS-LIMIT', 'WageCore/Sources/WageCore/Goals/GoalValidation.swift', r'goalAmountLimit: Decimal = 999999\b',
                 '目标金额最多 999999 (Allen 2026-11-26 定)，不设上限时金额输得极大 App 会卡死')
    card = 'WageCore/Sources/WageCore/Goals/GoalCard.swift'
    finish = lint.body(card, 'func finishDay(')
    inside = range(0)
    if finish is None:
        lint.fail('GOALS-LIMIT', card, '找不到 finishDay (改名了要同步改 ui_lint.py)')
    else:
        first = lint.read(card)[:lint.read(card).index(finish)].count('\n') + 1
        inside = range(first, first + finish.count('\n') + 1)
        # 注释掉的行不算数：只在真正的代码行里找。
        code = '\n'.join(line for line in finish.splitlines() if not line.lstrip().startswith('//'))
        if not re.search(r'guard[^\n]*days <= Decimal\(ActiveGoalCard\.estimateDayLimit\)[^\n]*else \{ return nil \}', code):
            lint.fail('GOALS-LIMIT', card, 'finishDay 开头要有 guard days <= Decimal(ActiveGoalCard.estimateDayLimit)：天数极大时转成整数会溢出，逐天数也数不完')
        if not re.search(r'through:[^\n]*estimateDayLimit', code):
            lint.fail('GOALS-LIMIT', card, 'finishDay 逐天数时截止日 (through:) 要按 estimateDayLimit 算，否则会一直数下去')
    lint.require('GOALS-LIMIT', card, r'func attendanceDay\(',
                 '找不到逐天数的 attendanceDay (改名了要同步改 ui_lint.py，否则「只能由 finishDay 调」这条查不到任何东西)')
    # 逐天数的 attendanceDay 只能在 finishDay 的函数体里调 (它先看上限)；按行号判断，注释里提到不算。
    for rel in lint.swift_files('WageCore/Sources'):
        for number, line in enumerate(lint.read(rel).splitlines(), 1):
            if 'attendanceDay(' not in line or line.lstrip().startswith('//') or 'func attendanceDay(' in line:
                continue
            if not (rel == card and number in inside):
                lint.fail('GOALS-LIMIT', f'{rel}:{number}', f'预计完成日要经 finishDay 数 (带天数上限)，不要直接调 attendanceDay：{line.strip()[:70]}')


def repository(lint):
    """仓库：本机专用的目录不能进 git。"""
    try:
        tracked = subprocess.run(['git', 'ls-files', 'roles', 'docs/spec'], capture_output=True, text=True, check=True, cwd=lint.root).stdout.split()
    except (OSError, subprocess.CalledProcessError):
        return  # 不在 git 仓库里 (自测用的临时目录) 时不查
    for path in tracked:
        lint.fail('REPO-LOCAL', path, 'roles/ 与 docs/spec/ 只放本机，不能进 git')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', default=os.path.dirname(os.path.dirname(HERE)))
    args = parser.parse_args()
    lint = Lint(os.path.abspath(args.root))
    try:
        for group in (restore_boundary, page_header, navigation, fonts, goals, repository):
            group(lint)
    except Blocked as blocked:
        print(f'BLOCKED: {blocked}')
        return 2
    for line in lint.failures:
        print(line)
    if lint.failures:
        print(f'ui_lint: {len(lint.failures)} 条不过')
        return 1
    print('ui_lint: 通过')
    return 0


if __name__ == '__main__':
    sys.exit(main())
