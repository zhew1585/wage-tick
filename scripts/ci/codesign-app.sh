#!/bin/zsh
# 发布前用 Developer ID 重签 App (ADR-0009)：编译仍是 ad-hoc 签名 (与 PR 检查一致)，这里从内到外换成正式签名，供公证。
#   - Sparkle 内部组件与框架：按 Sparkle 文档不带 entitlements 重签 (ad-hoc 构建给 Autoupdate 注入的
#     application-identifier 是受限 entitlement，没有描述文件会被系统杀掉)。
#   - 小组件扩展与 App：保留编译时的 entitlements，去掉公证不收的 get-task-allow；
#     App 再去掉 disable-library-validation (只为 ad-hoc 构建加载 Sparkle，同一 Team ID 签名后不需要)。
# 用法：scripts/ci/codesign-app.sh <App 路径> <签名身份 (SHA-1 或证书名)>
set -euo pipefail
APP="$1"
IDENTITY="$2"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }

# 取出 $1 当前的 entitlements，删掉其余参数列出的键，再按它重签 $1。
sign_keeping_entitlements() {
  local target="$1"; shift
  local plist="$WORK/$(basename "$target").plist"
  codesign -d --entitlements - --xml "$target" > "$plist" 2>/dev/null
  # 用 PlistBuddy 而不是 plutil：plutil 把键名里的点当成嵌套路径，删不掉。
  local key
  for key in com.apple.security.get-task-allow "$@"; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
  done
  sign --entitlements "$plist" "$target"
}

for helper in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  sign "$SPARKLE/Versions/B/$helper"
done
sign "$SPARKLE"

for appex in "$APP"/Contents/PlugIns/*.appex(N); do
  sign_keeping_entitlements "$appex"
done
sign_keeping_entitlements "$APP" com.apple.security.cs.disable-library-validation

codesign --verify --deep --strict --verbose=2 "$APP"
