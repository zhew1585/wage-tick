#!/bin/bash
# 界面检查里要 macOS 的那一半，由 scripts/checks/run.sh ui 调用。规则与每条对应的坑见 scripts/checks/README.md。
# 一次运行：编一份 Debug (关掉 hardened runtime，放临时目录) → 离屏渲染页面预览并量页头 → 用临时目录里的假数据拉起 App，
# 截真窗口图并量页头 → 在 App 进程里合成按键、点击跑交互回归 → 确认真实数据目录没被碰过。
# 不往 /Applications 写东西，不读写 ~/Library/Application Support/com.zhew1585.WageTick/ (只取校验和)，不申请任何系统权限。
# 用法：scripts/checks/ui-checks-mac.sh [输出目录]，也可用环境变量 UI_CHECKS_OUT；默认 build/ui-checks/。
#       UI_CHECKS_DERIVED_DATA=<目录>：复用一份已经编好的 Debug 构建 (要 ENABLE_HARDENED_RUNTIME=NO)，跳过编译 (selftest-mac.sh 不用它)。
# 退出码：0 全部通过；1 有规则不过 (编译失败也算)；2 blocked (缺工具、窗口没出现等环境问题)。
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT="$(pwd)"
OUT="${1:-${UI_CHECKS_OUT:-build/ui-checks}}"

blocked() { echo "BLOCKED: $*"; exit 2; }

[[ "$(uname)" == "Darwin" ]] || blocked "渲染与交互检查要在 macOS 上跑"
command -v xcodebuild >/dev/null || blocked "没有 xcodebuild"
command -v python3 >/dev/null || blocked "没有 python3"
command -v clang >/dev/null || blocked "没有 clang"
command -v swiftc >/dev/null || blocked "没有 swiftc"
command -v shasum >/dev/null || blocked "没有 shasum"

START=$(date +%s)
WORK="$(mktemp -d)"
APP_PID_FILE="${WORK}/app.pid"
# 收尾：只关自己拉起的 App (pid 记在临时目录里)，删临时目录。超时、Ctrl-C 也走这里。
cleanup() {
    if [[ -f "${APP_PID_FILE}" ]]; then
        local pid
        pid="$(cat "${APP_PID_FILE}")"
        if kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}" 2>/dev/null
            sleep 1
            kill -9 "${pid}" 2>/dev/null
        fi
    fi
    rm -rf "${WORK}"
}
trap cleanup EXIT
trap 'exit 2' INT TERM

rm -rf "${OUT}"
mkdir -p "${OUT}/offscreen" "${OUT}/realwindow"
OUT="$(cd "${OUT}" && pwd)"
LOG="${OUT}/ui-checks.log"
exec > >(tee "${LOG}") 2>&1
COMMIT="$(git rev-parse HEAD)"
echo "界面检查 (macOS)：提交 ${COMMIT:0:7}，输出 ${OUT}"

# 真实数据目录的校验和：文件名与内容。拉起 App 前后各取一次，变了就是碰了真实数据 (ENV-DATA)。
REAL_DATA="${HOME}/Library/Application Support/com.zhew1585.WageTick"
checksum() {
    if [[ -d "${REAL_DATA}" ]]; then
        (cd "${REAL_DATA}" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 2>/dev/null) | shasum -a 256 | cut -d' ' -f1
    else
        echo "(不存在)"
    fi
}
DATA_BEFORE="$(checksum)"

# 1. 编一次 Debug，离屏渲染与真窗口都用它。
APP_EXE_REL="Build/Products/Debug/牛马鼓励器.app/Contents/MacOS/WageTick"
if [[ -n "${UI_CHECKS_DERIVED_DATA:-}" ]]; then
    DD="${UI_CHECKS_DERIVED_DATA}"
    echo "复用构建：${DD}"
else
    DD="${WORK}/dd"
    echo "编译 Debug (ENABLE_HARDENED_RUNTIME=NO)…"
    if ! xcodebuild -project WageTick.xcodeproj -scheme WageTick -configuration Debug -derivedDataPath "${DD}" \
        -destination "platform=macOS,arch=$(uname -m)" ENABLE_HARDENED_RUNTIME=NO build -quiet > "${OUT}/build.log" 2>&1; then
        tail -30 "${OUT}/build.log"
        echo "FAIL [BUILD] Debug 编译失败，见 ${OUT}/build.log"
        exit 1
    fi
fi
EXE="${DD}/${APP_EXE_REL}"
[[ -x "${EXE}" ]] || blocked "构建目录里没有 App 可执行文件：${EXE}"

# 注入库与假状态生成器。
clang -fobjc-arc -dynamiclib -framework AppKit -o "${WORK}/libdrive.dylib" scripts/checks/harness/drive.m > "${OUT}/harness.log" 2>&1 \
    || { cat "${OUT}/harness.log"; blocked "注入库编不出来 (见 harness.log)"; }
cp scripts/checks/harness/FakeState.swift "${WORK}/main.swift"
swiftc -swift-version 6 -Onone -module-name FakeState -o "${WORK}/fakestate" \
    $(find WageCore/Sources/WageCore -name '*.swift') "${WORK}/main.swift" >> "${OUT}/harness.log" 2>&1 \
    || { tail -20 "${OUT}/harness.log"; echo "FAIL [BUILD] 假状态生成器编不过：核心的公开命令变了要同步改 scripts/checks/harness/FakeState.swift"; exit 1; }

# 假主目录：App 的状态、小组件数据、节假日缓存都落在这里。
FAKE_HOME="${WORK}/home"
"${WORK}/fakestate" "${FAKE_HOME}/Library/Application Support/com.zhew1585.WageTick/state.json" > /dev/null \
    || { echo "FAIL [BUILD] 假状态生成失败"; exit 1; }

echo "ok [BUILD] Debug 构建、注入库、假状态都就绪"

FAILED=0
BLOCKED_REASONS=()
record() {
    case "$1" in
        0) ;;
        1) FAILED=1 ;;
        *) BLOCKED_REASONS+=("$2") ;;
    esac
}

# 几何检查通过时，每条规则打一行 ok (不过时 ui_geometry.py 自己逐条打 FAIL)。
geometry() {
    local kind="$1" dir="$2" text code
    text="$(python3 scripts/checks/ui_geometry.py --kind "${kind}" --dir "${dir}" --manifest "${dir}/manifest.json")"
    code=$?
    echo "${text}"
    if [[ ${code} -eq 0 ]]; then
        local count
        count="$(ls "${dir}" | grep -c '\.png$')"
        echo "ok [HDR-FRAME] ${kind}：页头分隔线在 52pt"
        echo "ok [HDR-BACK] ${kind}：推进来的页面都有返回箭头"
        echo "ok [HDR-VCENTER] ${kind}：返回与标题在页头里垂直居中"
        echo "ok [HDR-LIGHTS-GAP] ${kind}：箭头离红绿灯大于 6pt"
        echo "ok [HDR-X] ${kind}：箭头、标题的横向位置与设计值一致"
        echo "ok [HDR-CONSISTENT] ${kind}：同类页面的页头一致"
        [[ "${kind}" == realwindow ]] && echo "ok [HDR-LIGHTS] realwindow：红绿灯右沿 72pt、中心 26pt"
        echo "ok [IMG-BLANK] ${kind}：${count} 张都不是空白图"
        echo "ok [IMG-KIND] ${kind}：图宽与有无红绿灯和截法相符"
        echo "ok [IMG-VERSION] ${kind}：清单里的提交是当前 HEAD"
        echo "ok [IMG-MANIFEST] ${kind}：清单字段齐全"
    fi
    return ${code}
}

# 2. 离屏渲染页面预览，量页头。
echo "离屏渲染页面预览…"
WAGETICK_RENDER_DIR="${OUT}/offscreen" CFFIXED_USER_HOME="${FAKE_HOME}" WAGETICK_FAKE_HOME="${FAKE_HOME}" \
    DYLD_INSERT_LIBRARIES="${WORK}/libdrive.dylib" "${EXE}" > "${OUT}/offscreen.log" 2>&1
RENDER=$?
if [[ ${RENDER} -ne 0 ]]; then
    cat "${OUT}/offscreen.log"
    record 2 "离屏渲染失败 (退出码 ${RENDER}，见 offscreen.log)"
else
    python3 - "${OUT}/offscreen" "${COMMIT}" <<'PY'
import datetime, json, os, sys
directory, commit = sys.argv[1], sys.argv[2]
files = sorted(name for name in os.listdir(directory) if name.endswith('.png'))
manifest = {
    'commit': commit,
    'kind': 'offscreen',
    'capturedAt': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
    'method': '离屏渲染：注入 Debug 版 App，调用 wagetick_render_page_previews (WageTick/Shared/PagePreviews.swift)，按屏幕倍数出图，四周留 24pt',
    'decorations': {'windowFrame': False, 'trafficLights': False},
    'files': files,
}
json.dump(manifest, open(os.path.join(directory, 'manifest.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
PY
    echo "· 几何 (离屏，$(ls "${OUT}/offscreen" | grep -c '\.png$') 张)"
    geometry offscreen "${OUT}/offscreen"
    record $? "离屏几何检查 blocked"
fi

# 3. 真窗口图与交互回归 (同一次启动)。
echo "拉起 App (假数据在临时目录)，截真窗口图并跑交互回归…"
python3 scripts/checks/ui_drive.py --exe "${EXE}" --dylib "${WORK}/libdrive.dylib" --home "${FAKE_HOME}" --workdir "${WORK}" --out "${OUT}"
DRIVE=$?
record ${DRIVE} "交互回归 blocked (见上面的 BLOCKED 行)"
if [[ -f "${OUT}/realwindow/manifest.json" ]]; then
    echo "· 几何 (真窗口)"
    geometry realwindow "${OUT}/realwindow"
    record $? "真窗口几何检查 blocked"
elif [[ ${DRIVE} -ne 2 ]]; then
    record 2 "没有真窗口图的清单"
fi

# 4. 真实数据目录前后一致。
DATA_AFTER="$(checksum)"
if [[ "${DATA_BEFORE}" != "${DATA_AFTER}" ]]; then
    if pgrep -x WageTick | grep -qv "^$(cat "${APP_PID_FILE}" 2>/dev/null)$"; then
        record 2 "真实数据目录在检查期间变了，但本机另有一个 App 在跑 (它自己会写)，没法判断是不是检查碰的"
    else
        echo "FAIL [ENV-DATA] 真实数据目录 ${REAL_DATA} 在检查期间变了 (${DATA_BEFORE} → ${DATA_AFTER})"
        FAILED=1
    fi
else
    echo "ok [ENV-DATA] 真实数据目录前后校验和一致"
fi

echo "耗时 $(( $(date +%s) - START )) 秒；图、清单、日志在 ${OUT}"
if [[ ${FAILED} -ne 0 ]]; then
    echo "ui-checks: 有规则不过"
    exit 1
fi
if [[ ${#BLOCKED_REASONS[@]} -gt 0 ]]; then
    for reason in "${BLOCKED_REASONS[@]}"; do echo "BLOCKED: ${reason}"; done
    exit 2
fi
echo "ui-checks: 通过"
exit 0
