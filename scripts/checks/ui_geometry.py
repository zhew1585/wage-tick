#!/usr/bin/env python3
"""界面几何与截图产物检查：只用标准库，直接读 PNG 像素量页头，不靠肉眼。

用法：
  python3 scripts/checks/ui_geometry.py --kind offscreen  --dir <页面预览目录> [--manifest <manifest.json>]
  python3 scripts/checks/ui_geometry.py --kind realwindow --dir <真窗口图目录> [--manifest <manifest.json>]
退出码：0 全部通过；1 有规则不过；2 blocked (缺图、缺清单、图读不了)，不能当作通过。
规则与每条对应的坑见 scripts/checks/README.md，阈值在 scripts/checks/ui-geometry.json。
"""
import argparse, json, os, struct, subprocess, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))


class Blocked(Exception):
    """缺图、缺清单这类没法判断的情况。"""


def load_png(path, max_rows=None):
    """读 8 位 RGB/RGBA/灰度 PNG 的前 max_rows 行，返回 (宽, 高, 已读行数, 取像素函数)。"""
    try:
        data = open(path, 'rb').read()
    except OSError as error:
        raise Blocked(f'读不了 {path}: {error}')
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise Blocked(f'{path} 不是 PNG')
    pos, idat, width, height, depth, color = 8, b'', None, None, None, None
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b'IHDR':
            width, height, depth, color = struct.unpack('>IIBB', chunk[:10])
        elif kind == b'IDAT':
            idat += chunk
    if depth not in (8, 16) or color not in (0, 2, 4, 6):
        raise Blocked(f'{path} 的像素格式不支持 (depth={depth}, color={color})')
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    step = depth // 8
    bpp = channels * step
    stride = width * bpp
    raw = zlib.decompress(idat)
    count = height if max_rows is None else min(height, max_rows)
    rows, prev, at = [], bytearray(stride), 0
    for _ in range(count):
        kind = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        if kind == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif kind == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif kind == 3:
            for x in range(stride):
                left = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 255
        elif kind == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(line)
        prev = line

    def pixel(x, y):
        o = x * bpp
        r = rows[y]
        return (r[o], r[o + step], r[o + 2 * step]) if channels >= 3 else (r[o],) * 3

    return width, height, count, pixel


def lum(p):
    return (p[0] + p[1] + p[2]) / 3


def runs(flags, gap):
    """把一行布尔值并成若干段 (起, 止)，中间断开不超过 gap 的算同一段。"""
    out, start, last = [], None, None
    for i, on in enumerate(flags):
        if on:
            if start is None:
                start = i
            last = i
        elif start is not None and i - last > gap:
            out.append((start, last))
            start = None
    if start is not None:
        out.append((start, last))
    return out


class Report:
    def __init__(self):
        self.failures, self.notes = [], []

    def fail(self, rule, where, text):
        self.failures.append(f'FAIL [{rule}] {where}: {text}')

    def note(self, text):
        self.notes.append(text)


def is_blank(pixel, width, rows, cfg):
    """整张图 (已读的部分) 几乎只有一种颜色。"""
    base = pixel(width // 2, 0)
    diff = total = 0
    for y in range(0, rows, 2):
        for x in range(0, width, 4):
            total += 1
            p = pixel(x, y)
            if abs(p[0] - base[0]) + abs(p[1] - base[1]) + abs(p[2] - base[2]) > 24:
                diff += 1
    return diff / max(total, 1) < cfg['blankMinDiffRatio']


def measure_header(pixel, width, rows, origin_x, origin_y, cfg):
    """量页头：分隔线、返回箭头与标题的墨迹。坐标换算成相对窗口左上角的 pt。"""
    scale = cfg['scale']
    to_pt_x = lambda px: (px - origin_x) / scale
    to_pt_y = lambda px: (px - origin_y) / scale
    x0, x1 = origin_x + 20 * scale, origin_x + 340 * scale
    divider = None
    for y in range(origin_y + 30 * scale, min(rows, origin_y + 100 * scale)):
        hits = sum(1 for x in range(x0, x1, 4) if 190 < lum(pixel(x, y)) < 243)
        if hits >= 0.9 * len(range(x0, x1, 4)):
            divider = y
            break
    if divider is None:
        return None
    top = origin_y + 4 * scale
    ink_left = origin_x + cfg['lightsRightEdgePt'] * scale + 2
    ink_right = origin_x + 250 * scale
    dark = lambda x, y: lum(pixel(x, y)) < cfg['inkLum']
    cols = [any(dark(x, y) for y in range(top, divider - 2)) for x in range(ink_left, ink_right)]
    segs = [(a + ink_left, b + ink_left + 1) for a, b in runs(cols, 3 * scale)]
    ys = [y for y in range(top, divider - 2) if any(dark(x, y) for x in range(ink_left, ink_right))]
    if not segs or not ys:
        return {'dividerPt': to_pt_y(divider), 'arrow': None, 'title': None}
    arrow = segs[0] if (segs[0][1] - segs[0][0]) <= 9 * scale and len(segs) > 1 else None
    title = segs[1] if arrow else segs[0]
    return {
        'dividerPt': to_pt_y(divider),
        'arrow': (to_pt_x(arrow[0]), to_pt_x(arrow[1])) if arrow else None,
        'titleLeft': to_pt_x(title[0]),
        'inkCenterY': (to_pt_y(ys[0]) + to_pt_y(ys[-1] + 1)) / 2,
        'frameCenterY': to_pt_y(divider) / 2,
    }


def measure_lights(pixel, origin_x, origin_y, cfg):
    """找系统红绿灯：在标题栏左边找三个约 12pt 宽、和底色不同的圆。返回三段 (左, 右) pt 与中心 y。"""
    scale = cfg['scale']
    # 横竖都从 4pt 搜起：标题栏改回 28 高时红绿灯在 x 8–60、中心 y 14，也要找得到，才能报 HDR-LIGHTS 而不是「没有红绿灯」。
    y0, y1 = origin_y + 4 * scale, origin_y + 38 * scale
    x0, x1 = origin_x + 4 * scale, origin_x + (cfg['lightsRightEdgePt'] + 4) * scale
    base = pixel(origin_x + 6 * scale, origin_y + 6 * scale)
    differs = lambda x, y: sum(abs(a - b) for a, b in zip(pixel(x, y), base)) > 30
    cols = [any(differs(x, y) for y in range(y0, y1)) for x in range(x0, x1)]
    segs = [(a + x0, b + x0 + 1) for a, b in runs(cols, 0)]
    discs = [s for s in segs if 9 * scale <= s[1] - s[0] <= 15 * scale]
    if len(discs) != 3:
        return None
    ys = [y for y in range(y0, y1) if any(differs(x, y) for x in range(discs[0][0], discs[2][1]))]
    return {
        'discs': [((a - origin_x) / scale, (b - origin_x) / scale) for a, b in discs],
        'centerY': ((ys[0] - origin_y) + (ys[-1] + 1 - origin_y)) / 2 / scale,
    }


def check_page(name, path, kind, cfg, report, screen_scale=2):
    """检查一张页面图；返回量到的页头 (供一致性比较)。

    screen_scale 是出图那块屏幕的倍数。真窗口图不论屏幕几倍都存成 2 倍 (1 倍屏的是放大的)，倍数由调用方给；
    离屏预览按屏幕倍数出图，倍数从图宽认，不看 screen_scale。1 倍屏上字按整像素对齐，容差按 ui-geometry.json 的 oneX 放宽。
    """
    margin = cfg['offscreenMarginPt'] if kind == 'offscreen' else 0
    width, height, rows, pixel = load_png(path, max_rows=(margin + 140) * cfg['scale'])
    full_width_pt = cfg['windowWidthPt'] + 2 * margin
    if kind == 'offscreen' and width == full_width_pt:
        screen_scale = 1
        cfg = {**cfg, 'scale': 1}
    elif kind == 'offscreen':
        screen_scale = 2
    scale = cfg['scale']
    origin = margin * scale
    expected_width = full_width_pt * scale
    one_x = cfg['oneX'] if screen_scale == 1 else {'verticalTolPt': cfg['verticalTolPt'], 'extraTolPt': 0}
    role = 'root' if name in cfg['root']['pages'] + cfg.get('formPages', []) else 'sub' if name in cfg['sub']['pages'] else None
    # 离屏预览里的弹出表单 (sheet) 本来就比窗口窄，图宽只对页面图与真窗口图查。
    if width != expected_width and (role or kind == 'realwindow'):
        wanted = f'{expected_width}px (2 倍屏) 或 {full_width_pt}px (1 倍屏)' if kind == 'offscreen' else f'{expected_width}px'
        report.fail('IMG-KIND', name, f'图宽 {width}px，{kind} 应是 {wanted}：不是这种截法出的图，或缩放不对')
        return None
    if is_blank(pixel, width, rows, cfg):
        report.fail('IMG-BLANK', name, '图是空白的 (几乎只有一种颜色)')
        return None
    # 窗口宽的图才找红绿灯；比窗口窄的表单图标题栏位置上是表单自己的标题字，会被认成圆。
    lights = measure_lights(pixel, origin, origin, cfg) if width == expected_width else None
    if kind == 'offscreen' and lights:
        report.fail('IMG-KIND', name, '标成离屏预览的图里出现了红绿灯，标识与内容不符')
    if kind == 'realwindow':
        if not lights:
            report.fail('IMG-KIND', name, '标成真窗口的图里没找到三个系统红绿灯 (可能是离屏图冒充，或截到了别的东西)')
            return None
        right = lights['discs'][2][1]
        if abs(right - cfg['lightsRightEdgePt']) > 1.5:
            report.fail('HDR-LIGHTS', name, f"红绿灯右沿在 {right:.1f}pt，配置里是 {cfg['lightsRightEdgePt']}pt，标题栏方案变了要同步更新规则")
        expected_y = cfg['titlebarHeightPt'] / 2
        if abs(lights['centerY'] - expected_y) > 1:
            report.fail('HDR-LIGHTS', name, f"红绿灯中心 y={lights['centerY']:.2f}pt，应在 {expected_y}pt (52 高标题栏里垂直居中，Allen 已接受)")
    if role is None:
        return None
    header = measure_header(pixel, width, rows, origin, origin, cfg)
    if header is None:
        report.fail('HDR-FRAME', name, '没找到页头分隔线')
        return None
    if abs(header['dividerPt'] - cfg['titlebarHeightPt']) > 1.5:
        report.fail('HDR-FRAME', name, f"页头分隔线在 {header['dividerPt']:.1f}pt，应在 {cfg['titlebarHeightPt']}pt 左右 (页头不能排在红绿灯下面多出的一行里)")
    if header.get('arrow') is None:
        report.fail('HDR-BACK', name, '页头里没找到返回箭头 (推进来的页面都要能返回)')
        return header
    offset = header['inkCenterY'] - header['frameCenterY']
    if abs(offset) > one_x['verticalTolPt']:
        report.fail('HDR-VCENTER', name, f"返回与标题的墨迹中心偏离页头框中心 {offset:+.2f}pt，超过 ±{one_x['verticalTolPt']}pt")
    rule = cfg[role]
    left, right = header['arrow']
    gap_lights = left - cfg['lightsRightEdgePt']
    if gap_lights <= cfg['lightsGapRejectedPt']:
        report.fail('HDR-LIGHTS-GAP', name, f"返回箭头离红绿灯只有 {gap_lights:.1f}pt；{cfg['lightsGapRejectedPt']}pt 已被 Allen 明确否掉 (太近)")
    tol = rule['tolPt'] + one_x['extraTolPt']
    if abs(left - rule['arrowLeftPt']) > tol:
        report.fail('HDR-X', name, f"返回箭头墨迹左沿在 {left:.1f}pt，设计值 {rule['arrowLeftPt']}pt ±{tol}")
    gap_title = header['titleLeft'] - right
    low, high = rule['arrowTitleGapPt']
    if not low <= gap_title <= high:
        report.fail('HDR-X', name, f'返回箭头到标题的间隙 {gap_title:.1f}pt，应在 {low}–{high}pt')
    if header['titleLeft'] > rule['maxTitleLeftPt']:
        report.fail('HDR-X', name, f"标题墨迹左沿在 {header['titleLeft']:.1f}pt，超过 {rule['maxTitleLeftPt']}pt (过度右移)")
    if kind == 'realwindow' and lights and abs(lights['centerY'] - header['inkCenterY']) > one_x['verticalTolPt']:
        report.fail('HDR-VCENTER', name, f"红绿灯中心 y={lights['centerY']:.2f} 与标题墨迹中心 y={header['inkCenterY']:.2f} 不在一条线上")
    header['role'] = role
    header['screenScale'] = screen_scale
    return header


def check_manifest(path, directory, kind, report):
    """产物清单：记录图是哪个提交、哪种方式截的。版本不对、缺文件都不能过。"""
    try:
        manifest = json.load(open(path, encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise Blocked(f'读不了清单 {path}: {error}')
    for key in ('commit', 'kind', 'capturedAt', 'method', 'files'):
        if key not in manifest:
            report.fail('IMG-MANIFEST', path, f'清单缺字段 {key}')
    if manifest.get('kind') != kind:
        report.fail('IMG-KIND', path, f"清单写的是 {manifest.get('kind')}，按 {kind} 检查")
    try:
        head = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True, cwd=HERE).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise Blocked(f'取不到当前提交: {error}')
    commit = str(manifest.get('commit', ''))
    if len(commit) < 7 or not head.startswith(commit):
        report.fail('IMG-VERSION', path, f'图来自提交 {commit or "(空)"}，当前是 {head[:7]}：不能拿别的版本的图当这一版的')
    for name in manifest.get('files', []):
        if not os.path.isfile(os.path.join(directory, name)):
            raise Blocked(f'清单里的 {name} 不在 {directory}')
    scale = manifest.get('screenScale', 2)
    if scale not in (1, 2):
        report.fail('IMG-MANIFEST', path, f'清单里的 screenScale 是 {scale!r}，只认 1 或 2')
        scale = 2
    return scale


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--kind', choices=['offscreen', 'realwindow'], required=True)
    parser.add_argument('--dir', required=True)
    parser.add_argument('--manifest')
    parser.add_argument('--config', default=os.path.join(HERE, 'ui-geometry.json'))
    parser.add_argument('--only', nargs='*', help='只查这些图 (自测用)，不要求整套齐全')
    parser.add_argument('--screen-scale', type=int, choices=[1, 2], help='真窗口图出图那块屏幕的倍数 (自测用)；平时从清单的 screenScale 读，没写按 2')
    args = parser.parse_args()
    cfg = json.load(open(args.config, encoding='utf-8'))
    report = Report()
    try:
        screen_scale = args.screen_scale or 2
        if args.manifest:
            screen_scale = args.screen_scale or check_manifest(args.manifest, args.dir, args.kind, report)
        elif not args.only:
            raise Blocked('没给产物清单 (--manifest)，没法确认这些图是哪一版、怎么截的')
        wanted = args.only or (cfg['root']['pages'] + cfg['sub']['pages'] + cfg['otherPages'][args.kind])
        headers = {}
        checked = 0
        for name in wanted:
            path = os.path.join(args.dir, name + '.png')
            if not os.path.isfile(path):
                if args.kind == 'realwindow' and name in cfg['realwindowOptional']:
                    report.note(f'MANUAL {name}: 没有真窗口图，这一页的红绿灯关系需人工看')
                    continue
                raise Blocked(f'缺图 {path}')
            checked += 1
            header = check_page(name, path, args.kind, cfg, report, screen_scale)
            if header and header.get('arrow'):
                headers[name] = header
        for role in ('root', 'sub'):
            group = {n: h for n, h in headers.items() if h.get('role') == role}
            if len(group) > 1:
                lefts = [h['arrow'][0] for h in group.values()]
                centers = [h['inkCenterY'] for h in group.values()]
                if max(lefts) - min(lefts) > 0.5:
                    report.fail('HDR-CONSISTENT', role, f'同类页面的返回箭头左沿不一致：{ {n: round(h["arrow"][0], 1) for n, h in group.items()} }')
                if max(centers) - min(centers) > 0.75:
                    report.fail('HDR-CONSISTENT', role, f'同类页面的页头墨迹中心 y 不一致：{ {n: round(h["inkCenterY"], 2) for n, h in group.items()} }')
    except Blocked as blocked:
        print(f'BLOCKED: {blocked}')
        return 2
    for line in report.failures + report.notes:
        print(line)
    if any(h['screenScale'] == 1 for h in headers.values()):
        print(f"NOTE: 这些图出自 1 倍屏：字按整像素对齐，标题比 2 倍屏上低约 1pt；垂直容差按 ±{cfg['oneX']['verticalTolPt']}pt、箭头左沿容差多放 {cfg['oneX']['extraTolPt']}pt。")
    print(f"MANUAL: 留白是否美观要 Allen 看真窗口图确认；这里只保证不退回被否掉的 {cfg['lightsGapRejectedPt']}pt、并与当前设计值一致。")
    if report.failures:
        print(f'ui_geometry: {len(report.failures)} 条不过')
        return 1
    print(f'ui_geometry: 通过 ({args.kind}，查了 {checked} 张)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
