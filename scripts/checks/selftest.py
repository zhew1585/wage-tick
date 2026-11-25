#!/usr/bin/env python3
"""检查脚本自己的回归：故意违规必须被抓到，正确的必须放行。

用法：python3 scripts/checks/selftest.py
- 静态规则：把仓库源码拷到临时目录，逐条做一处「故意违规」的改动，确认 ui_lint.py 以退出码 1 报出对应的规则；不改时通过。
- 几何规则：用这几轮真实出过问题的图 (fixtures/，从当时的渲染图上截下来的顶部一条) 确认 ui_geometry.py 报出对应的规则。
退出码：0 全部符合预期；1 有规则该报没报、或不该报却报了。
"""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# (说明, 文件, 原文, 改成, 必须报出的规则)。原文为 None 表示在文件末尾追加；说明以「*」开头表示把文件里所有出现的地方都换掉。
LINT_VIOLATIONS = [
    ('外壳里又用了大胆版的 HeroTheme', 'WageTick/Panel/PanelSections.swift', None, '\nlet leaked = HeroTheme.orange\n', 'RESTORE-BOLD'),
    ('外壳里又用了胶囊按钮', 'WageTick/Panel/TodayPanelView.swift', None, '\n// .buttonStyle(.pill(.ink))\n', 'RESTORE-BOLD'),
    ('已到手页回来了', 'WageTick/Goals/GoalsView.swift', None, '\nstruct GoalEarnedView {}\n', 'RESTORE-EARNED'),
    ('独立窗口回来了', 'WageTick/Settings/SettingsPage.swift', None, '\nfinal class SettingsWindowController {}\n', 'RESTORE-WINDOWS'),
    ('*核心里删了搬砖天数', 'WageCore/Sources/WageCore/Goals/GoalList.swift', 'workDaysText', 'removedText', 'CORE-KEPT'),
    ('请假扣薪文字又改回减号', 'WageCore/Sources/WageCore/Snapshot/LeaveForm.swift',
     'deductionText = "= \\(Format.money(settlement.leaveDeduction))"', 'deductionText = Format.deductionOrZero(settlement.leaveDeduction)', 'COPY-LEAVE'),
    ('首页页头忘了 isRoot', 'WageTick/Goals/GoalsView.swift', 'PageHeader("目标", back: close, isRoot: true)', 'PageHeader("目标", back: close)', 'HDR-CALLER'),
    ('页头不带返回', 'WageTick/Settings/SettingsView.swift', 'PageHeader("设置", back: close, isRoot: true)', 'PageHeader("设置", isRoot: true)', 'HDR-CALLER'),
    ('下一级页头用了首页排法', 'WageTick/History/DayDetailView.swift', 'PageHeader(detail.title, back: back)', 'PageHeader(detail.title, back: back, isRoot: true)', 'HDR-CALLER'),
    ('新页面用了页头却没登记', 'WageTick/Panel/PanelFooter.swift', None, '\nprivate let unregistered = PageHeader("新页面", back: {})\n', 'HDR-CALLER'),
    ('窗口改回标准标题栏', 'WageTick/Panel/TodayPanelWindowController.swift', 'titlebar: .tall, rootView: view', 'titlebar: .standard, rootView: view', 'HDR-TITLEBAR'),
    ('页面预览上方又多留一行', 'WageTick/Shared/PagePreviews.swift',
     '            view\n                .frame(width: size.width, height: size.height)',
     '            view\n                .padding(.top, 28)\n                .frame(width: size.width, height: size.height)', 'HDR-TITLEBAR'),
    ('盖页后底层没停用', 'WageTick/Panel/TodayPanelView.swift', '                .disabled(content.page != nil)\n', '', 'NAV-COVER'),
    ('Esc 兜底不分下一级', 'WageTick/Panel/TodayPanelWindowController.swift', 'if !goBackInside(page) { pop() }', 'pop()', 'NAV-ESC'),
    ('Esc 兜底不管表单', 'WageTick/Panel/TodayPanelWindowController.swift',
     '        if content.route != .home {\n            content.route = .home\n            return true\n        }\n        return false', '        return false', 'NAV-ESC'),
    ('开着表单也换页', 'WageTick/Panel/TodayPanelWindowController.swift', '} else if !hasSheet {\n                push(page)', '} else {\n                push(page)', 'NAV-SHEET'),
    ('点 Dock 图标也退页', 'WageTick/App/AppDelegate.swift', 'todayPanel.show(returnsToOverview: false)', 'todayPanel.show()', 'NAV-DOCK'),
    ('概览目标卡不可点', 'WageTick/Panel/GoalCardView.swift',
     'Button(action: openGoals) { ActiveGoalCardView(goal: goal).contentShape(Rectangle()) }', 'ActiveGoalCardView(goal: goal)', 'NAV-GOALCARD'),
    ('历史页退场清空内容', 'WageTick/History/HistoryPage.swift',
     '        isActive = false\n        timer?.invalidate()\n        timer = nil\n    }\n\n    /// 退一级',
     '        isActive = false\n        timer?.invalidate()\n        timer = nil\n        content.snapshot = nil\n    }\n\n    /// 退一级', 'NAV-HISTORY'),
    ('退场后定时器又被拉起', 'WageTick/Goals/GoalsPage.swift', '        guard isActive else { return }\n', '', 'NAV-TIMER'),
]

# (说明, 截图方式, fixtures 下的目录, 要查的图, 预期退出码, 必须报出的规则)
GEOMETRY_CASES = [
    ('箭头离红绿灯 6pt (84b2b71，Allen 说太近)', 'offscreen', 'offscreen-tight-84b2b71', ['P3-goals', 'P4-history'], 1, ['HDR-LIGHTS-GAP', 'HDR-X']),
    ('标题比原版靠右 26pt (947880d，Allen 说偏右)', 'offscreen', 'offscreen-right-947880d', ['P3-goals'], 1, ['HDR-X']),
    ('页头排在红绿灯下面多出的一行 (73f794d，Allen 说偏下)', 'offscreen', 'offscreen-extra-row-73f794d', ['P3-goals'], 1, ['HDR-FRAME']),
    ('原版月日历页头', 'offscreen', 'offscreen-original-9c69fd3', ['P5-calendar'], 0, []),
    ('离屏的弹出表单图：比窗口窄，表单标题的字不当红绿灯', 'offscreen', 'offscreen-sheets-023eb31', ['P6-settings-payday-sheet', 'P6-settings-rest-mode-sheet', 'P5-unpaid-work-form-overnight'], 0, []),
    ('箭头落在原版内容起点、离红绿灯 13pt 的首页页头 (d107b63)', 'offscreen', 'offscreen-d107b63', ['P3-goals', 'P4-history', 'P6-settings'], 0, []),
    ('同上，真窗口图 (d107b63)', 'realwindow', 'realwindow-d107b63', ['today', 'P3-goals', 'P4-history'], 0, []),
    ('真窗口图里箭头离红绿灯 6pt (84b2b71)', 'realwindow', 'realwindow-tight-84b2b71', ['P3-goals'], 1, ['HDR-LIGHTS-GAP']),
    ('真窗口的概览：红绿灯在 52 高标题栏里居中', 'realwindow', 'realwindow-tight-84b2b71', ['today'], 0, []),
    ('裁成空白的近景 (3d73c4c 里的 goals-titlebar.png)', 'realwindow', 'realwindow-blank', ['P3-goals'], 1, ['IMG-BLANK']),
    ('把真窗口图标成离屏预览', 'offscreen', 'realwindow-tight-84b2b71', ['P3-goals'], 1, ['IMG-KIND']),
    ('把离屏预览标成真窗口图', 'realwindow', 'offscreen-original-9c69fd3', ['P5-calendar'], 1, ['IMG-KIND']),
    ('没给产物清单', 'offscreen', 'offscreen-original-9c69fd3', None, 2, ['BLOCKED']),
    ('缺图', 'offscreen', 'realwindow-blank', ['P4-history'], 2, ['BLOCKED']),
]


def run(script, *args):
    result = subprocess.run([sys.executable, os.path.join(HERE, script), *args], capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def copy_sources(target):
    for directory in ('WageTick', 'WageTickWidgets', 'WageCore'):
        shutil.copytree(os.path.join(ROOT, directory), os.path.join(target, directory),
                        ignore=lambda base, names: [n for n in names if not (os.path.isdir(os.path.join(base, n)) or n.endswith(('.swift', '.ttf')))])


def main():
    problems = []
    with tempfile.TemporaryDirectory() as temp:
        copy_sources(temp)
        code, output = run('ui_lint.py', '--root', temp)
        if code != 0:
            problems.append(f'当前源码本身就不过静态规则 (退出码 {code})，先按下面的输出改源码，自测的故意违规部分这时不可信：\n{output}')
        for title, rel, old, new, rule in LINT_VIOLATIONS:
            path = os.path.join(temp, rel)
            original = open(path, encoding='utf-8').read()
            if old is None:
                changed = original + new
            elif title.startswith('*') and old in original:
                changed = original.replace(old, new)
            elif original.count(old) != 1:
                problems.append(f'「{title}」：{rel} 里要改的那段找不到或不唯一，自测本身要跟着源码更新')
                continue
            else:
                changed = original.replace(old, new)
            open(path, 'w', encoding='utf-8').write(changed)
            code, output = run('ui_lint.py', '--root', temp)
            open(path, 'w', encoding='utf-8').write(original)
            if code != 1 or f'[{rule}]' not in output:
                problems.append(f'「{title}」应该被 {rule} 抓到，实际退出码 {code}：\n{output}')
            else:
                print(f'ok   静态 {rule:<16} 抓到：{title}')
    for title, kind, directory, only, expected, rules in GEOMETRY_CASES:
        args = ['--kind', kind, '--dir', os.path.join(HERE, 'fixtures', directory)]
        if only:
            args += ['--only', *only]
        code, output = run('ui_geometry.py', *args)
        missing = [rule for rule in rules if rule not in output]
        if code != expected or missing:
            problems.append(f'「{title}」预期退出码 {expected}、报出 {rules}，实际退出码 {code}：\n{output}')
        else:
            print(f"ok   几何 {'/'.join(rules) or '通过':<16} {'抓到' if expected else '放行'}：{title}")
    if problems:
        print('\n'.join(['', *problems]))
        print(f'selftest: {len(problems)} 处不符合预期')
        return 1
    print(f'selftest: 全部符合预期 ({len(LINT_VIOLATIONS)} 条静态违规、{len(GEOMETRY_CASES)} 组图)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
