#!/usr/bin/env python3
"""FONT-BUNDLED：App 进程里界面字体、数字字体实际用的字体文件必须在 App 包内，各字重在 wght 轴上取得准。

报告由 App 里 Debug 才有的 wagetick_font_report() 给出 (WageTick/Theme/AppFontReport.swift)，注入库取出：
离屏渲染完写进 <渲染目录>/fonts.json；真窗口由 ui_drive.py 用 font 命令取，调用本模块的 check()。
用法：python3 scripts/checks/ui_font.py --report <fonts.json> --where <哪一处，打在结果行里>
退出码：0 通过；1 不过；2 blocked (没有报告)。
"""
import argparse, json, os, sys

FAMILIES = {'ui': '界面字体', 'num': '数字字体'}


def check(report, where):
    """返回 (退出码, 结果行)。"""
    if not isinstance(report, dict) or 'error' in report or not report.get('fonts'):
        return 2, [f'BLOCKED: FONT-BUNDLED {where}：没取到字体报告 ({(report or {}).get("error", "报告是空的")})']
    bundle = report.get('bundle', '').rstrip('/')
    lines, files = [], {}
    for font in report['fonts']:
        name = FAMILIES.get(font['family'], font['family'])
        path, weight, wght = font.get('path') or '', font['weight'], font.get('wght')
        if not bundle or not path.startswith(bundle + '/'):
            lines.append(f'FAIL [FONT-BUNDLED] {where}：{name} {weight} 用的是 {path or "(取不到文件路径)"} ({font.get("postScriptName")})，不在 App 包 {bundle} 内')
            continue
        if wght is None or abs(wght - weight) > 0.5:
            lines.append(f'FAIL [FONT-BUNDLED] {where}：{name} {weight} 在 wght 轴上实际是 {wght}，字重没取准 ({os.path.basename(path)})')
            continue
        files.setdefault(name, set()).add(os.path.basename(path))
    fallback = report.get('fallback', {}).get('postScriptName', '')
    if not fallback.startswith('PingFang'):
        lines.append(f'FAIL [FONT-BUNDLED] {where}：子集外的汉字回退到 {fallback or "(没有)"} ({report.get("fallback", {}).get("path")})，应是苹方')
    if lines:
        return 1, lines
    used = '，'.join(f'{name} {"、".join(sorted(names))}' for name, names in files.items())
    return 0, [f'ok [FONT-BUNDLED] {where}：{used} 都在 App 包内，各字重 wght 取准；子集外的汉字回退到 {fallback}']


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', required=True)
    parser.add_argument('--where', required=True)
    args = parser.parse_args()
    try:
        report = json.load(open(args.report, encoding='utf-8'))
    except (OSError, ValueError) as error:
        report = {'error': str(error)}
    code, lines = check(report, args.where)
    print('\n'.join(lines))
    return code


if __name__ == '__main__':
    sys.exit(main())
