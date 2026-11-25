#!/bin/bash
# ui-checks-mac.sh 自己的回归 (慢，十几分钟，不进 CI)：在临时 worktree 里逐条做「故意违规」的源码改动，
# 每条都跑一遍 scripts/checks/run.sh ui，确认以退出码 1 报出对应的规则；跑完把改动还原，最后删掉临时 worktree。
# 先跑一遍不改的，必须通过 (退出码 0)，否则后面的结果没意义。
# 用法：scripts/checks/selftest-mac.sh [只跑名字里含这段文字的改动]
# 退出码：0 每条都抓到；1 有没抓到的 (表里如实列出)；2 blocked。
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"
[[ "$(uname)" == "Darwin" ]] || { echo "BLOCKED: 要在 macOS 上跑"; exit 2; }

TMP="$(mktemp -d)"
TREE="${TMP}/tree"
cleanup() {
    git -C "${ROOT}" worktree remove --force "${TREE}" >/dev/null 2>&1
    rm -rf "${TMP}"
}
trap cleanup EXIT
trap 'exit 2' INT TERM

# 检出当前提交，再把工作区里的 scripts/checks 盖上去 (检查脚本没提交的改动也要测到)。
git worktree add --detach "${TREE}" HEAD >/dev/null 2>&1 || { echo "BLOCKED: 建不了临时 worktree"; exit 2; }
rsync -a --delete --exclude __pycache__ "${ROOT}/scripts/checks/" "${TREE}/scripts/checks/"

python3 - "${TREE}" "${TMP}" "${1:-}" <<'PY'
import os, re, subprocess, sys, time

tree, tmp, only = sys.argv[1], sys.argv[2], sys.argv[3]

# (名字, 文件, 原文, 改成, 预期报出的规则 (任一即算抓到), 说明)
CASES = [
    ('箭头离红绿灯 6pt', 'WageTick/Components/PageHeader.swift',
     'WindowChrome.Titlebar.tall.leadingInset + Spacing.s1', 'WindowChrome.Titlebar.tall.leadingInset - Spacing.s6',
     ('HDR-LIGHTS-GAP', 'HDR-X'), 'PageHeader.rootLeading 改回 leadingInset - 6'),
    ('窗口改回标准标题栏', 'WageTick/Panel/TodayPanelWindowController.swift',
     'titlebar: .tall, rootView: view', 'titlebar: .standard, rootView: view',
     ('HDR-LIGHTS', 'HDR-VCENTER'), '今日概览窗口用 .standard (28) 标题栏'),
    ('页面预览上方多留一行', 'WageTick/Shared/PagePreviews.swift',
     '            view\n                .frame(width: size.width, height: size.height)',
     '            view\n                .padding(.top, 28)\n                .frame(width: size.width, height: size.height)',
     ('HDR-FRAME',), 'PagePreviews.page() 上方加 28 的 padding'),
    ('盖页后底层没停用', 'WageTick/Panel/TodayPanelView.swift',
     '                .disabled(content.page != nil)\n', '',
     ('ACT-COVER',), 'TodayPanelView 去掉 .disabled(content.page != nil)'),
    ('开着表单也换页', 'WageTick/Panel/TodayPanelWindowController.swift',
     '} else if !hasSheet {\n                push(page)', '} else {\n                push(page)',
     ('ACT-SHEET',), 'show() 里 push 不再受 hasSheet 保护'),
    ('Esc 兜底直接退回概览', 'WageTick/Panel/TodayPanelWindowController.swift',
     'if !goBackInside(page) { pop() }', 'pop()',
     ('ACT-ESC',), 'handleCancel() 不先退页面里的下一级'),
    ('概览目标卡不可点', 'WageTick/Panel/GoalCardView.swift',
     'Button(action: openGoals) { ActiveGoalCardView(goal: goal).contentShape(Rectangle()) }\n                    .buttonStyle(.highlight(radius: Radius.card))',
     'ActiveGoalCardView(goal: goal).contentShape(Rectangle())',
     ('ACT-GOALCARD',), 'GoalCardView 的累计中卡片去掉 Button 包裹'),
    ('点 Dock 图标也退页', 'WageTick/App/AppDelegate.swift',
     'todayPanel.show(returnsToOverview: false)', 'todayPanel.show()',
     ('ACT-DOCK',), 'applicationShouldHandleReopen 改回 todayPanel.show()'),
    ('⌘1 不回概览', 'WageTick/Panel/TodayPanelWindowController.swift',
     '        } else if isOpen, !hasSheet, returnsToOverview {\n            pop()\n        }\n', '        }\n',
     ('ACT-HOME',), 'show() 里去掉 pop() 那个分支'),
    ('历史页再进来不是月列表', 'WageTick/History/HistoryPage.swift',
     '        content.selectedMonth = nil\n        content.selectedDay = nil\n        refresh()', '        refresh()',
     ('ACT-HISTORY',), 'HistoryPage.appear() 不重置 selectedMonth / selectedDay'),
]


def run(label):
    out = os.path.join(tmp, re.sub(r'\W+', '-', label))
    started = time.time()
    proc = subprocess.run(['scripts/checks/run.sh', 'ui'], cwd=tree, capture_output=True, text=True, errors='replace',
                          env=dict(os.environ, UI_CHECKS_OUT=out))
    text = proc.stdout + proc.stderr
    rules = sorted(set(re.findall(r'FAIL \[([A-Z0-9-]+)\]', text)))
    return proc.returncode, rules, round(time.time() - started), text


rows, missed = [], 0
code, rules, seconds, text = run('baseline')
print(f'基线 (不改)：退出码 {code}，{seconds} 秒，报出 {rules or "无"}', flush=True)
if code != 0:
    print(text[-3000:])
    print('BLOCKED: 不改源码时 run.sh ui 就不通过，后面的故意违规没法判断')
    sys.exit(2)

for name, path, old, new, expected, change in CASES:
    if only and only not in name:
        continue
    file = os.path.join(tree, path)
    source = open(file, encoding='utf-8').read()
    if source.count(old) != 1:
        print(f'BLOCKED: {name}：{path} 里找不到要改的原文 (源码变了，要同步改 selftest-mac.sh)')
        sys.exit(2)
    open(file, 'w', encoding='utf-8').write(source.replace(old, new))
    try:
        code, rules, seconds, text = run(name)
    finally:
        subprocess.run(['git', 'checkout', '--', path], cwd=tree, check=True)
    caught = code == 1 and any(rule in rules for rule in expected)
    missed += not caught
    rows.append((name, change, '/'.join(expected), code, rules, caught))
    print(f'{"抓到" if caught else "没抓到"}  {name}：退出码 {code}，报出 {", ".join(rules) or "无"}，{seconds} 秒', flush=True)
    for line in [line for line in text.splitlines() if line.startswith(('FAIL', 'BLOCKED'))][:6]:
        print('    ' + line[:300])

print('\n| 改动 | 改了什么 | 预期规则 | 退出码 | 实际报出 | 抓到 |')
print('|---|---|---|---|---|---|')
for name, change, expected, code, rules, caught in rows:
    print(f'| {name} | {change} | {expected} | {code} | {", ".join(rules) or "无"} | {"是" if caught else "否"} |')
print(f'\nselftest-mac: {len(rows) - missed}/{len(rows)} 条抓到')
sys.exit(1 if missed else 0)
PY
