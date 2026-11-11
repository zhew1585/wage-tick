#!/bin/zsh
# 启动检查 (ADR-0008)：CI 与发布前确认编好的 App 真能跑起来，单靠编译通过发现不了签名、框架加载这类问题
# (例如 hardened runtime 拒绝加载 Sparkle.framework，App 一打开就退出)。
# 检查：签名完整、带着 Sparkle 与小组件扩展、启动 15 秒后进程还在。启动时关掉自动检查更新，免得 CI 里去下载更新。
# 用法：scripts/ci/smoke-test.sh <牛马鼓励器.app>
set -euo pipefail
APP="$1"
WAIT=15

fail() { print -u2 -- "启动检查失败：$1"; exit 1; }

codesign --verify --deep --strict "$APP" || fail "签名不完整"
[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || fail "缺少 Sparkle.framework"
[[ -n "$(print -l "$APP"/Contents/PlugIns/*.appex(N))" ]] || fail "缺少小组件扩展"

executable="$APP/Contents/MacOS/$(plutil -extract CFBundleExecutable raw "$APP/Contents/Info.plist")"
log=$(mktemp)
# 命令行参数进 UserDefaults 的参数域，只对这次启动生效，不改动存下来的设置。
"$executable" -SUEnableAutomaticChecks NO >"$log" 2>&1 &
pid=$!
sleep $WAIT
if ! kill -0 $pid 2>/dev/null; then
  cat "$log"
  fail "App 启动后 $WAIT 秒内退出了"
fi
kill $pid
wait $pid 2>/dev/null || true
print -- "启动检查通过：App 运行 $WAIT 秒正常"
