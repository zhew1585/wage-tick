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
    lint.require('HDR-TITLEBAR', controller, r'titlebarInset: WindowChrome\.Titlebar\.standard\.height',
                 '概览与原地表单的内容仍从 28 处排起 (titlebarInset 取标准标题栏高度)')
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
    lint.require('NAV-GOALCARD', 'WageTick/Panel/GoalCardView.swift', r'case \.active\(let goal\):\s*(//[^\n]*\n\s*)*Button\(action: openGoals\)',
                 '概览上累计中目标的卡片要能点进目标页 (Allen 2026-11-26 定)')
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
        for group in (restore_boundary, page_header, navigation, repository):
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
