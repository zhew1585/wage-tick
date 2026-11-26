#!/usr/bin/env python3
"""检查脚本自己的回归：故意违规必须被抓到，正确的必须放行。

用法：python3 scripts/checks/selftest.py
- 静态规则：把仓库源码拷到临时目录，逐条做一处「故意违规」的改动，确认 ui_lint.py 以退出码 1 报出对应的规则；不改时通过。
- 几何规则：按这几轮真实出过问题的渲染图上量到的位置，现画出只有色块的页面图，确认 ui_geometry.py 报出对应的规则。仓库里不放图片。
退出码：0 全部符合预期；1 有规则该报没报、或不该报却报了。
"""
import json, os, shutil, struct, subprocess, sys, tempfile, zlib

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

WINDOW, MARGIN, INK, PAPER = 360, 24, (60, 40, 30), (255, 253, 248)


def write_png(path, width, height, rects, background=PAPER):
    """画一张 8 位 RGB 的 PNG：rects 是 [(左, 上, 右, 下, 颜色)]，单位像素，后画的盖住先画的。"""
    rows = [bytearray(bytes(background) * width) for _ in range(height)]
    for x0, y0, x1, y1, color in rects:
        x0, x1 = max(0, x0), min(width, x1)
        for y in range(max(0, y0), min(height, y1)):
            rows[y][x0 * 3:x1 * 3] = bytes(color) * (x1 - x0)
    chunk = lambda kind, data: struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    raw = b''.join(b'\x00' + bytes(row) for row in rows)
    with open(path, 'wb') as out:
        out.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                  + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def draw_page(path, shot, arrow=(85, 91.5), title=100.5, divider=51, ink_y=26.25, lights=(20, 26), header=True, width=WINDOW, blank=False, scale=2):
    """画一张页面图的顶部 120pt，位置单位是相对窗口左上角的 pt，画成 scale 倍图 (离屏预览在 1 倍屏上出的是 1 倍图)。

    shot：offscreen 四周留 24pt 白边、不画红绿灯；realwindow 贴边、在 lights=(最左一个圆的左沿, 中心 y) 画三个 12pt 的圆 (画成方块)。
    页头：返回箭头 arrow=(左, 右) 与标题 (左沿 title、宽 30pt) 的墨迹块以 ink_y 为中心，下面是 divider 处的分隔线；
    arrow=None 不画箭头，header=False 整个页头都不画 (概览、弹出表单)。blank=True 只画底色。
    默认值是 d107b63 真实渲染图上量到的：箭头 85–91.5、标题 100.5、分隔线 51、墨迹中心 26.25、红绿灯 20–72 中心 26。
    """
    margin = MARGIN if shot == 'offscreen' else 0
    px = lambda pt: round((pt + margin) * scale)
    rects = []
    if not blank:
        rects.append((px(0), px(0), px(width), px(120), PAPER))
        rects.append((px(20), px(64), px(width - 20), px(110), (120, 160, 220)))
        if header:
            rects.append((px(0), px(divider), px(width), px(divider) + scale, (232, 228, 220)))
            rects.append((px(title), px(ink_y - 8), px(title + 30), px(ink_y + 8), INK))
            if arrow:
                rects.append((px(arrow[0]), px(ink_y - 7), px(arrow[1]), px(ink_y + 7), INK))
        if lights:
            rects += [(px(lights[0] + 20 * i), px(lights[1] - 6), px(lights[0] + 20 * i + 12), px(lights[1] + 6), (205, 205, 205)) for i in range(3)]
    write_png(path, (width + 2 * margin) * scale, (120 + 2 * margin) * scale, rects, background=PAPER if shot == 'realwindow' else (255, 255, 255))


OFF, REAL = {'shot': 'offscreen', 'lights': None}, {'shot': 'realwindow'}
SUB = {'arrow': (90, 96.5), 'title': 112, 'ink_y': 26}       # 原版 9c69fd3 月日历页头的实测值
TIGHT = {'arrow': (78, 84.5), 'title': 92.5}                 # 84b2b71：箭头离红绿灯 6pt
# 1 倍屏 (PR #34 的 CI 实测)：字按整像素对齐，箭头 86–92，标题低约 1pt
ONE_X = {'arrow': (86, 92), 'title': 102, 'ink_y': 27.25}
# 弹出表单的离屏图：比窗口窄，没有页头，表单标题的三个字正好落在红绿灯的位置上
SHEET = {'shot': 'offscreen', 'header': False, 'width': 320}

# (说明, 按哪种截法查, {图名: draw_page 的参数}, 预期退出码, 必须报出的规则)。图是自测时现画的，位置数值取自当时真实渲染图上量到的。
GEOMETRY_CASES = [
    ('箭头离红绿灯 6pt (84b2b71，Allen 说太近)', 'offscreen', {'P3-goals': {**OFF, **TIGHT}, 'P4-history': {**OFF, **TIGHT, 'title': 90}}, 1, ['HDR-LIGHTS-GAP', 'HDR-X']),
    ('标题比原版靠右 26pt (947880d，Allen 说偏右)', 'offscreen', {'P3-goals': {**OFF, 'arrow': (90, 96.5), 'title': 114}}, 1, ['HDR-X']),
    ('页头排在红绿灯下面多出的一行 (73f794d，Allen 说偏下)', 'offscreen', {'P3-goals': {**OFF, 'arrow': None, 'title': 73, 'divider': 79, 'ink_y': 54.5}}, 1, ['HDR-FRAME']),
    ('页头没有返回箭头', 'offscreen', {'P6-settings': {**OFF, 'arrow': None}}, 1, ['HDR-BACK']),
    ('返回与标题偏下 3pt', 'offscreen', {'P3-goals': {**OFF, 'ink_y': 29.25}}, 1, ['HDR-VCENTER']),
    ('目标与历史的箭头位置差 1pt', 'offscreen', {'P3-goals': {**OFF}, 'P4-history': {**OFF, 'arrow': (86, 92.5), 'title': 101.5}}, 1, ['HDR-CONSISTENT']),
    ('原版月日历页头', 'offscreen', {'P5-calendar': {**OFF, **SUB}}, 0, []),
    ('离屏的弹出表单图：比窗口窄，表单标题的字不当红绿灯', 'offscreen', {'P6-settings-payday-sheet': {**SHEET}, 'P5-unpaid-work-form-overnight': {**SHEET, 'width': 280}}, 0, []),
    ('箭头落在原版内容起点、离红绿灯 13pt 的首页页头 (d107b63)', 'offscreen', {'P3-goals': {**OFF, 'title': 103}, 'P4-history': {**OFF}, 'P6-settings': {**OFF, 'ink_y': 26.5}}, 0, []),
    ('同上，真窗口图 (d107b63)', 'realwindow', {'today': {**REAL, 'header': False}, 'P3-goals': {**REAL, 'title': 103}, 'P4-history': {**REAL}}, 0, []),
    ('真窗口图里箭头离红绿灯 6pt (84b2b71)', 'realwindow', {'P3-goals': {**REAL, **TIGHT}}, 1, ['HDR-LIGHTS-GAP']),
    ('标题栏改回 28 高：红绿灯在 8–60、中心 14', 'realwindow', {'today': {**REAL, 'header': False, 'lights': (8, 14)}}, 1, ['HDR-LIGHTS']),
    ('1 倍屏上的离屏预览：箭头 86、标题低约 1pt，放行', 'offscreen', {'P3-goals': {**OFF, **ONE_X, 'scale': 1}, 'P4-history': {**OFF, **ONE_X, 'title': 101, 'scale': 1}}, 0, []),
    ('1 倍屏上的离屏预览，箭头离红绿灯 6pt', 'offscreen', {'P3-goals': {**OFF, **TIGHT, 'scale': 1}}, 1, ['HDR-LIGHTS-GAP', 'HDR-X']),
    ('1 倍屏上的离屏预览，返回与标题偏下 4pt', 'offscreen', {'P3-goals': {**OFF, **ONE_X, 'ink_y': 30.25, 'scale': 1}}, 1, ['HDR-VCENTER']),
    ('1 倍屏上的真窗口图 (存成 2 倍)，清单标了 1 倍屏，放行', 'realwindow', {'P3-goals': {**REAL, **ONE_X}, 'screen-scale': 1}, 0, []),
    ('同一张图当成 2 倍屏：标题低 1pt 多，不放行', 'realwindow', {'P3-goals': {**REAL, **ONE_X}}, 1, ['HDR-VCENTER']),
    ('裁成空白的近景 (3d73c4c 里的 goals-titlebar.png)', 'realwindow', {'P3-goals': {**REAL, 'blank': True}}, 1, ['IMG-BLANK']),
    ('把真窗口图标成离屏预览', 'offscreen', {'P3-goals': {**REAL}}, 1, ['IMG-KIND']),
    ('把离屏预览标成真窗口图', 'realwindow', {'P5-calendar': {**OFF, **SUB}}, 1, ['IMG-KIND']),
    ('离屏预览那么宽的图里画着红绿灯', 'offscreen', {'P3-goals': {**OFF, 'lights': (20, 26)}}, 1, ['IMG-KIND']),
    ('真窗口那么宽的图里没有红绿灯', 'realwindow', {'P3-goals': {**REAL, 'lights': None}}, 1, ['IMG-KIND']),
    ('清单里的提交不是当前这一版，还缺截法', 'offscreen', {'P3-goals': {**OFF}, 'manifest': {'commit': '0000000', 'kind': 'offscreen', 'capturedAt': '2026-11-26T00:00:00Z', 'files': ['P3-goals.png']}}, 1, ['IMG-VERSION', 'IMG-MANIFEST']),
    ('没给产物清单', 'offscreen', {'P5-calendar': {**OFF, **SUB}, 'whole-set': True}, 2, ['BLOCKED']),
    ('缺图', 'offscreen', {'P4-history': None}, 2, ['BLOCKED']),
]


def run_geometry_case(kind, pages):
    """把一组图画到临时目录里，跑 ui_geometry.py。pages 里图名对 None 表示故意不画；manifest、whole-set、screen-scale 是这一组的选项。"""
    pages = dict(pages)
    manifest, whole_set, screen_scale = pages.pop('manifest', None), pages.pop('whole-set', False), pages.pop('screen-scale', None)
    with tempfile.TemporaryDirectory() as directory:
        for name, spec in pages.items():
            if spec is not None:
                draw_page(os.path.join(directory, name + '.png'), **spec)
        args = ['--kind', kind, '--dir', directory]
        if manifest:
            path = os.path.join(directory, 'manifest.json')
            json.dump(manifest, open(path, 'w', encoding='utf-8'))
            args += ['--manifest', path]
        if not whole_set:
            args += ['--only', *pages]
        if screen_scale:
            args += ['--screen-scale', str(screen_scale)]
        return run('ui_geometry.py', *args)


# 首页各区域 (窗口坐标 pt)：与 ui-home.json 的 bands 相同，自测里按它画，再逐项挪动做反例。
HOME = {'bar': (238, 248), 'button': (216, 264), 'stats': (280, 344), 'goals': (356, 460), 'actions': (472, 516), 'footer': (528, 574)}
SURFACE, LINE_COLOR, MONEY, SOFT, ACCENT = (245, 240, 230), (231, 223, 209), (43, 138, 62), (253, 235, 221), (232, 89, 12)
INK_COLOR = (31, 27, 22)


def draw_home(path, kind='working', height=574, scale=2, **moved):
    """画一张首页预览图 (整窗 360×height，四周 24pt 白边)，只有色块。kind：working 画进度条，offwork 画白干计时按钮，rest 两样都不画，
    empty 把累计中目标卡换成描边的空状态卡。moved 里给某个区域新的 (上沿, 下沿) 就是把它挪了位置。"""
    bands = {**HOME, **moved}
    px = lambda pt: round((pt + 24) * scale)
    box = lambda x0, band, x1, color: (px(x0), px(band[0]), px(x1), px(band[1]), color)
    rects = [(px(0), px(0), px(360), px(height), PAPER)]
    if kind in ('working', 'empty'):
        rects += [box(20, bands['bar'], 340, LINE_COLOR), box(20, bands['bar'], 150, MONEY)]
    elif kind == 'offwork':
        rects.append(box(20, bands['button'], 340, INK_COLOR))
    rects.append(box(20, bands['stats'], 340, SURFACE))
    top, bottom = bands['goals']
    if kind == 'empty':
        rects += [box(20, (top, bottom), 340, LINE_COLOR), box(21, (top + 1, bottom - 1), 339, PAPER)]
    else:
        rects += [box(20, (top, bottom), 228, SOFT), box(34, (bottom - 20, bottom - 14), 154, ACCENT),
                  box(236, (top, top + 48), 340, LINE_COLOR), box(237, (top + 1, top + 47), 339, PAPER)]
    rects += [box(20, bands['actions'], 175, SURFACE), box(185, bands['actions'], 340, SURFACE), box(0, bands['footer'], 360, SURFACE)]
    write_png(path, (360 + 48) * scale, (height + 48) * scale, rects, background=(255, 255, 255))


# (说明, {图名: draw_home 的参数}, 预期退出码, 必须报出的规则)
HOME_CASES = [
    ('首页各状态区域位置一致', {'P2-working': {}, 'P2-off-work': {'kind': 'offwork'}, 'P2-rest-day': {'kind': 'rest'},
                      'P2-first-half-leave-no-goal': {'kind': 'empty'}}, 0, []),
    ('1 倍屏上的首页图', {'P2-working': {'scale': 1}, 'P2-off-work': {'kind': 'offwork', 'scale': 1}}, 0, []),
    ('已下班时统计卡被按钮顶下去 4pt', {'P2-off-work': {'kind': 'offwork', 'stats': (284, 348)}}, 1, ['HOME-BAND']),
    ('只有 1 个目标时目标卡变高', {'P2-working': {'goals': (356, 480)}}, 1, ['HOME-BAND']),
    ('没有目标时空状态卡变矮', {'P2-first-half-leave-no-goal': {'kind': 'empty', 'goals': (356, 440)}}, 1, ['HOME-BAND']),
    ('情绪按钮被上面的内容推下去', {'P2-working': {'actions': (480, 524)}}, 1, ['HOME-BAND']),
    ('入口栏不贴底', {'P2-working': {'footer': (520, 566)}}, 1, ['HOME-BAND']),
    ('进度条挪了位置', {'P2-working': {'bar': (244, 254)}}, 1, ['HOME-BAND']),
    ('白干计时按钮撑满进度区', {'P2-off-work': {'kind': 'offwork', 'button': (212, 268)}}, 1, ['HOME-BAND']),
    ('窗口高度改回 760', {'P2-working': {'height': 760}}, 1, ['HOME-SIZE']),
    ('缺图', {'P2-working': None}, 2, ['BLOCKED']),
]


def run_home_case(pages):
    with tempfile.TemporaryDirectory() as directory:
        for name, spec in pages.items():
            if spec is not None:
                draw_home(os.path.join(directory, name + '.png'), **spec)
        return run('ui_home.py', '--dir', directory, '--only', *pages)


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
    for title, kind, pages, expected, rules in GEOMETRY_CASES:
        code, output = run_geometry_case(kind, pages)
        missing = [rule for rule in rules if rule not in output]
        if code != expected or missing:
            problems.append(f'「{title}」预期退出码 {expected}、报出 {rules}，实际退出码 {code}：\n{output}')
        else:
            print(f"ok   几何 {'/'.join(rules) or '通过':<16} {'抓到' if expected else '放行'}：{title}")
    for title, pages, expected, rules in HOME_CASES:
        code, output = run_home_case(pages)
        missing = [rule for rule in rules if rule not in output]
        if code != expected or missing:
            problems.append(f'「{title}」预期退出码 {expected}、报出 {rules}，实际退出码 {code}：\n{output}')
        else:
            print(f"ok   首页 {'/'.join(rules) or '通过':<16} {'抓到' if expected else '放行'}：{title}")
    if problems:
        print('\n'.join(['', *problems]))
        print(f'selftest: {len(problems)} 处不符合预期')
        return 1
    print(f'selftest: 全部符合预期 ({len(LINT_VIOLATIONS)} 条静态违规、{len(GEOMETRY_CASES)} 组页头图、{len(HOME_CASES)} 组首页图)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
