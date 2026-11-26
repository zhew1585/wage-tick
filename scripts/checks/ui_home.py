#!/usr/bin/env python3
"""今日概览首页的区域检查：各状态下每个区域的位置都一样，不随内容挪动。只用标准库，直接读渲染图的像素。

用法：python3 scripts/checks/ui_home.py --dir <首页预览目录> --manifest <manifest.json>
退出码：0 全部通过；1 有规则不过；2 blocked (缺图、缺清单、图读不了)，不能当作通过。
规则与对应的坑见 scripts/checks/README.md，位置在 scripts/checks/ui-home.json (与 WageTick/Theme/Metrics.swift 的 HomeLayout 同一组数)。

图是 scripts/render-panel-previews.sh 那种离屏渲染：整个窗口的内容 (含标题栏那一段)，四周各留 24pt 白边，按屏幕倍数出图。
认区域靠底色：统计卡、情绪按钮、入口栏是 surface 色，累计中目标卡是 accentSoft 色，空状态卡与排队卡是 line 色描边，
进度条是 line 与 money 色，白干计时按钮是 ink 色。
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
    found = {}

    def expect(key, band, label):
        want = cfg['bands'][key]
        if band is None:
            report.fail('HOME-BAND', name, f'没找到{label} (应在 {want[0]}–{want[1]}pt)')
            return
        found[key] = band
        if abs(band[0] - want[0]) > tol or abs(band[1] - want[1]) > tol:
            report.fail('HOME-BAND', name, f'{label}在 {band[0]:g}–{band[1]:g}pt，应在 {want[0]}–{want[1]}pt：各区域在所有状态下位置都要一样')

    stats = cfg['bands']['stats']
    expect('stats', image.band(sum(stats) / 2, 36, 324, [colors['surface']], 0.5), '统计卡')
    footer = cfg['bands']['footer']
    expect('footer', image.band(sum(footer) / 2, 8, 352, [colors['surface']], 0.55), '入口栏')
    if name not in cfg['noActions']:
        actions = cfg['bands']['actions']
        expect('actions', image.band(sum(actions) / 2, 36, 150, [colors['surface']], 0.4, reach_pt=10), '情绪按钮')
    goals = cfg['bands']['goals']
    # 累计中目标卡：在卡片左内边距里的一窄条上量 (x 28–31，圆角 12 在这里已经收平，旗子与文字从 32 起)，不受卡片里内容多少影响。
    card = image.band(sum(goals) / 2, 28, 31, [colors['accentSoft']], 0.99)
    if card is None:
        # 没有累计中目标：空状态卡是 line 色描边，上下各一条 1pt 的线。
        top = image.band(goals[0], 40, 320, [colors['line']], 0.8, reach_pt=12)
        bottom = image.band(goals[1], 40, 320, [colors['line']], 0.8, reach_pt=12)
        card = (top[0], bottom[1]) if top and bottom else None
    expect('goals', card, '攒钱队列')
    if name not in cfg['noProgress']:
        bar = cfg['bands']['progressBar']
        button = cfg['bands']['progressButton']
        got = image.band(sum(button) / 2, 36, 324, [colors['ink']], 0.55, reach_pt=4)
        if got:
            expect('progressButton', got, '白干计时按钮')
        else:
            expect('progressBar', image.band(sum(bar) / 2, 24, 336, [colors['line'], colors['money'], colors['surface']], 0.9, reach_pt=6), '进度条')
    return found


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
