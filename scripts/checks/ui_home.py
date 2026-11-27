#!/usr/bin/env python3
"""今日概览首页的区域检查：各状态下每个区域的位置都一样，不随内容挪动。只用标准库，直接读渲染图的像素。

用法：python3 scripts/checks/ui_home.py --dir <首页预览目录> --manifest <manifest.json>
退出码：0 全部通过；1 有规则不过；2 blocked (缺图、缺清单、图读不了)，不能当作通过。
规则与对应的坑见 scripts/checks/README.md，位置在 scripts/checks/ui-home.json (与 WageTick/Theme/Metrics.swift 的 HomeLayout 同一组数)。

图是 scripts/render-panel-previews.sh 那种离屏渲染：整个窗口的内容 (含标题栏那一段)，四周各留 24pt 白边，按屏幕倍数出图。
认区域靠底色：统计卡、情绪按钮、入口栏是 surface 色，累计中目标卡是 accentSoft 色，空状态卡与排队卡是 line 色描边，
进度条是 line 与 money 色 (白干进度是 loss 色)，已下班的「我还没走」与白干中的「终于下班了」是 ink 色。
"""
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from ui_geometry import Blocked, Report, check_manifest, load_png  # noqa: E402


def close(pixel, color, tol):
    return abs(pixel[0] - color[0]) + abs(pixel[1] - color[1]) + abs(pixel[2] - color[2]) <= tol


class Image:
    """一张首页图：按窗口坐标 (pt) 问某一行里某种颜色占多少。"""

    def __init__(self, path, cfg):
        self.width, self.height, self.rows, self.pixel = load_png(path)
        margin = cfg['marginPt']
        width_pt = cfg['windowPt'][0] + 2 * margin
        self.scale = 2 if self.width == width_pt * 2 else 1 if self.width == width_pt else None
        self.margin = margin
        self.cfg = cfg

    def size_ok(self):
        w, h = self.cfg['windowPt']
        return self.scale is not None and self.height == (h + 2 * self.margin) * self.scale

    def row_share(self, y_px, x0_pt, x1_pt, colors):
        """第 y_px 行 (图上的像素行) 在窗口横向 x0–x1 之间，颜色属于 colors 之一的像素占比。"""
        tol = self.cfg['colorTol']
        xs = range(round((x0_pt + self.margin) * self.scale), round((x1_pt + self.margin) * self.scale), self.scale)
        hits = sum(1 for x in xs if any(close(self.pixel(x, y_px), c, tol) for c in colors))
        return hits / max(len(xs), 1)

    def band(self, around_pt, x0_pt, x1_pt, colors, share, reach_pt=40):
        """在窗口纵向 around_pt 附近找一段连续的行，每行 colors 的占比都不低于 share；返回 (上沿, 下沿) pt，找不到为 None。"""
        to_px = lambda pt: round((pt + self.margin) * self.scale)
        to_pt = lambda px: px / self.scale - self.margin
        ok = lambda y: 0 <= y < self.rows and self.row_share(y, x0_pt, x1_pt, colors) >= share
        start = next((y for d in range(0, reach_pt * self.scale) for y in (to_px(around_pt) + d, to_px(around_pt) - d) if ok(y)), None)
        if start is None:
            return None
        top = bottom = start
        while ok(top - 1):
            top -= 1
        while ok(bottom + 1):
            bottom += 1
        return to_pt(top), to_pt(bottom + 1)


def check_state(name, path, cfg, report):
    """检查一张首页图，返回量到的各区域 (供各状态之间比较)。"""
    colors = {k: tuple(v) for k, v in cfg['colors'].items()}
    tol = cfg['tolPt']
    image = Image(path, cfg)
    if not image.size_ok():
        w, h = cfg['windowPt']
        report.fail('HOME-SIZE', name, f"图是 {image.width}×{image.height}px，应是窗口 {w}×{h}pt 四周各加 {cfg['marginPt']}pt 的 1 倍或 2 倍图："
                                       '窗口高度变了要同步改 ui-home.json 与 Metrics.swift 的 HomeLayout')
        return None
    # 先查有没有被横向撑宽：撑宽了的话各区域左沿都跟着偏，下面按固定横坐标量出来的上下沿不可信，报了反而误导。
    if not check_width(name, image, cfg['bands']['stats'], colors, cfg, report):
        return None
    found = {}

    def expect(key, band, label, bottom_extra=0):
        want = cfg['bands'][key]
        if band is None:
            report.fail('HOME-BAND', name, f'没找到{label} (应在 {want[0]}–{want[1]}pt)')
            return
        found[key] = band
        if abs(band[0] - want[0]) > tol or abs(band[1] - want[1]) > tol + bottom_extra:
            report.fail('HOME-BAND', name, f'{label}在 {band[0]:g}–{band[1]:g}pt，应在 {want[0]}–{want[1]}pt：各区域在所有状态下位置都要一样')

    stats = cfg['bands']['stats']
    # 统计卡、情绪按钮、入口栏都在各自左内边距里的一窄条上量：那里没有文字和图标，圆角也已经收平，不受内容多少影响。
    expect('stats', image.band(sum(stats) / 2, 31, 35, [colors['surface']], 0.99), '统计卡')
    footer = cfg['bands']['footer']
    # 入口栏在左内边距里量 (三个入口从 x 20 起)。窗口左下角是圆角，预览图的窗框描边在这里会多吃掉半个到 1 个 pt，
    # 再加上描边本身占最下面 1pt，所以下沿多容 1pt (Mac 上 2 倍图量到 572.5)。
    expect('footer', image.band(sum(footer) / 2, 14, 18, [colors['surface']], 0.99), '入口栏', bottom_extra=1)
    unpaid = name in cfg['unpaidWork']
    if name not in cfg['noActions']:
        actions = cfg['bands']['actions']
        # 左边那一颗的底色：白干计时中是墨色主按钮「终于下班了」，其余状态是 surface 色的次要按钮。
        # 量在 x 28–31：左边避开按钮 8pt 的圆角，右边不碰请假状态那颗从 32 起的伞图标。
        left = {key: image.band(sum(actions) / 2, 28, 31, [colors[key]], 0.99, reach_pt=10) for key in ('ink', 'surface')}
        expect('actions', left['ink'] or left['surface'], '情绪按钮')
        if unpaid and left['ink'] is None and left['surface']:
            report.fail('HOME-UNPAID', name, '白干计时中情绪按钮区左边应是墨色主按钮「终于下班了」，现在是次要按钮：停止计时的按钮不在这一排，或这一排又放回了「今天扣钱了」')
        if not unpaid and left['ink']:
            report.fail('HOME-UNPAID', name, '情绪按钮区左边是墨色主按钮：只有白干计时中 (登记在 ui-home.json 的 unpaidWork) 这一排才放「终于下班了」')
    goals = cfg['bands']['goals']
    # 累计中目标卡：在卡片左内边距里的一窄条上量 (x 28–31，圆角 12 在这里已经收平，旗子与文字从 32 起)，不受卡片里内容多少影响。
    card = image.band(sum(goals) / 2, 28, 31, [colors['accentSoft']], 0.99)
    if card is None:
        # 没有累计中目标：空状态卡是 line 色描边，上下各一条 1pt 的线。
        top = image.band(goals[0], 40, 320, [colors['line']], 0.8, reach_pt=12)
        bottom = image.band(goals[1], 40, 320, [colors['line']], 0.8, reach_pt=12)
        card = (top[0], bottom[1]) if top and bottom else None
    expect('goals', card, '攒钱队列')
    if 'goals' in found:
        check_goal_date(name, image, found['goals'], colors, cfg, report)
    if name not in cfg['noProgress']:
        bar = cfg['bands']['progressBar']
        button = cfg['bands']['progressButton']
        got = image.band(sum(button) / 2, 36, 324, [colors['ink']], 0.55, reach_pt=4)
        if got and name not in cfg['offWork']:
            report.fail('HOME-UNPAID', name, '进度区是墨色按钮：只有已下班 (登记在 ui-home.json 的 offWork) 的进度区放「我还没走」；'
                                             '白干计时中是进度条，「终于下班了」在情绪按钮区')
        if not got and name in cfg['offWork']:
            report.fail('HOME-UNPAID', name, '已下班的进度区没找到墨色按钮「我还没走」')
        if got:
            expect('progressButton', got, '白干计时按钮')
        else:
            # 填充色分开认：白干进度是 loss 色，上班中是 money 色，用错了颜色这一条就量不到。
            fills = [colors[key] for key in ('line', 'loss' if unpaid else 'money', 'surface')]
            expect('progressBar', image.band(sum(bar) / 2, 24, 336, fills, 0.9, reach_pt=6), '进度条')
    return found


def check_width(name, image, stats, colors, cfg, report):
    """首页内容的左右沿：在统计卡该在的那一行 (按规格的位置) 上量它的左沿与右沿，没撑宽返回 True。某一块里的内容太宽 (比如带年份的预计日期) 会把整页撑宽、
    左右边距变窄；纵向的 HOME-BAND 查不出来。"""
    tol = cfg['colorTol']
    y = round((sum(stats) / 2 + image.margin) * image.scale)
    xs = [x for x in range(image.width) if close(image.pixel(x, y), colors['surface'], tol)]
    if not xs:
        return True  # 这一行没有统计卡：位置不对由 HOME-BAND 报
    left, right = xs[0] / image.scale - image.margin, (xs[-1] + 1) / image.scale - image.margin
    want = cfg['contentXPt']
    if abs(left - want[0]) > cfg['tolPt'] or abs(right - want[1]) > cfg['tolPt']:
        report.fail('HOME-WIDTH', name, f'统计卡横向在 {left:g}–{right:g}pt，应在 {want[0]}–{want[1]}pt：有内容把首页撑宽了，左右边距不再是 20')
        return False
    return True


def check_goal_date(name, image, goals, colors, cfg, report):
    """左侧大目标卡最下面一行：预计日期的字底要和进度条的下沿在同一条线上 (Allen 2026-11-26 专门提过)。
    「左大卡 + 右边小卡」的排法 (2 个及以上目标) 查这一条；只有 1 个目标的整宽卡，日期在金额那一行，查它和金额的字底 (见 check_wide_date)。"""
    tol = cfg['colorTol']
    to_px = lambda pt: round((pt + image.margin) * image.scale)
    middle = to_px(sum(goals) / 2)
    if not close(image.pixel(to_px(24), middle), colors['accentSoft'], tol):
        return
    if close(image.pixel(to_px(232), middle), colors['accentSoft'], tol):
        check_wide_date(name, image, goals, cfg, report)
        return
    bar = image.band(goals[1] - 16, 40, 140, [colors['accent'], colors['line']], 0.9, reach_pt=14)
    if bar is None:
        report.fail('HOME-GOALDATE', name, '大目标卡里没找到进度条')
        return
    ink_rows = [y for y in range(to_px(bar[0] - 12), to_px(bar[1] + 8))
                if any(sum(image.pixel(x, y)) / 3 < 190 for x in range(to_px(160), to_px(218)))]
    if not ink_rows:
        # 没法预计的状态 (登记在 noGoalDate) 本来就没有日期；其余状态量不到日期就是日期丢了或挪走了，不能当作通过。
        if name not in cfg['noGoalDate']:
            report.fail('HOME-GOALDATE', name, '大目标卡的进度条右边没量到预计日期：日期被去掉、挪走或颜色变浅了；这个状态本来就没法预计的话登记到 ui-home.json 的 noGoalDate')
        return
    date_bottom = (ink_rows[-1] + 1) / image.scale - image.margin
    limit = cfg['goalDateTolPt'] + (0.5 if image.scale == 1 else 0)
    if abs(date_bottom - bar[1]) > limit:
        report.fail('HOME-GOALDATE', name, f'大目标卡里预计日期的字底在 {date_bottom:g}pt，进度条下沿在 {bar[1]:g}pt，相差超过 {limit:g}pt：两者要对齐在一条线上')


def check_wide_date(name, image, goals, cfg, report):
    """只有 1 个目标的整宽卡：金额那一行右边的预计日期，字底要和左边累计额的字底在同一条线上 (Allen 2026-11-27 实机验收提的)。
    按文字基线对齐时汉字的字底比数字低约 1pt，所以日期要上提。累计额是 ink 色，后面的「/ 目标额」和日期是 muted 色：
    左边只认 ink 色 (平均亮度低于 100)，右边认 muted 色 (低于 165)，都相当于盖住像素六成以上才算。"""
    to_px = lambda pt: round((pt + image.margin) * image.scale)
    rows = range(to_px(goals[0] + 36), to_px(goals[1] - 24))
    dark = lambda x, y, limit: sum(image.pixel(x, y)) / 3 < limit
    amount = [y for y in rows if any(dark(x, y, 100) for x in range(to_px(34), to_px(200)))]
    date = [y for y in rows if any(dark(x, y, 165) for x in range(to_px(230), to_px(326)))]
    if not amount:
        report.fail('HOME-GOALDATE', name, '整宽目标卡的金额那一行没量到累计额')
        return
    if not date:
        if name not in cfg['noGoalDate']:
            report.fail('HOME-GOALDATE', name, '整宽目标卡的金额那一行右边没量到预计日期：日期被去掉、挪走或颜色变浅了；这个状态本来就没法预计的话登记到 ui-home.json 的 noGoalDate')
        return
    amount_bottom, date_bottom = ((ys[-1] + 1) / image.scale - image.margin for ys in (amount, date))
    limit = cfg['goalDateTolPt'] + (0.5 if image.scale == 1 else 0)
    if abs(date_bottom - amount_bottom) > limit:
        report.fail('HOME-GOALDATE', name, f'整宽目标卡里预计日期的字底在 {date_bottom:g}pt，累计额的字底在 {amount_bottom:g}pt，相差超过 {limit:g}pt：两者要对齐在一条线上')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dir', required=True)
    parser.add_argument('--manifest')
    parser.add_argument('--config', default=os.path.join(HERE, 'ui-home.json'))
    parser.add_argument('--only', nargs='*', help='只查这些图 (自测用)，不要求整套齐全')
    args = parser.parse_args()
    cfg = json.load(open(args.config, encoding='utf-8'))
    report = Report()
    try:
        if args.manifest:
            check_manifest(args.manifest, args.dir, 'panel', report)
        elif not args.only:
            raise Blocked('没给产物清单 (--manifest)，没法确认这些图是哪一版、怎么截的')
        checked = 0
        for name in args.only or cfg['states']:
            path = os.path.join(args.dir, name + '.png')
            if not os.path.isfile(path):
                raise Blocked(f'缺图 {path}')
            checked += 1
            check_state(name, path, cfg, report)
    except Blocked as blocked:
        print(f'BLOCKED: {blocked}')
        return 2
    for line in report.failures:
        print(line)
    if report.failures:
        print(f'ui_home: {len(report.failures)} 条不过')
        return 1
    print(f'ui_home: 通过 (查了 {checked} 张，各区域位置一致)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
