#!/bin/bash
# 界面规则检查的统一入口，本机与 CI 都走这里。规则与每条对应的坑见 scripts/checks/README.md。
# 用法：scripts/checks/run.sh static   只读源码，反例图现画，哪里都能跑 (CI「核心测试」里跑)
#       scripts/checks/run.sh ui       要 macOS 与 Xcode：渲染、量页头、真窗口与交互回归 (CI「App 编译与启动」里跑)
#       scripts/checks/run.sh all      两样都跑
# 退出码：0 通过；1 有规则不过；2 blocked (缺工具、缺图，没法判断)。blocked 不算通过。
set -uo pipefail
cd "$(dirname "$0")/../.."

static() {
    command -v python3 >/dev/null || { echo "BLOCKED: 没有 python3"; return 2; }
    # 先查当前源码：违规直接在这里报出来，说清是哪条规则、哪个文件。
    python3 scripts/checks/ui_lint.py || return $?
    # 再自测：故意违规必须被抓到。规则自己坏了的话，上面的「通过」不可信。
    python3 scripts/checks/selftest.py
}

ui() {
    [[ "$(uname)" == "Darwin" ]] || { echo "BLOCKED: 渲染与交互检查要在 macOS 上跑"; return 2; }
    [[ -x scripts/checks/ui-checks-mac.sh ]] || { echo "BLOCKED: 缺 scripts/checks/ui-checks-mac.sh"; return 2; }
    scripts/checks/ui-checks-mac.sh
}

case "${1:-}" in
    static) static ;;
    ui) ui ;;
    all) static && ui ;;
    *) echo "用法：$0 static|ui|all"; exit 64 ;;
esac
