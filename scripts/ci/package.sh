#!/bin/zsh
# 把编好的 App 打成两个发布文件 (ADR-0007)：
#   WageTick-<版本>.dmg  首次安装用，打开后把 App 拖进「应用程序」；
#   WageTick-<版本>.zip  Sparkle 自动更新下载的包 (ditto 压缩，保留签名与扩展属性)。
# 用法：scripts/ci/package.sh <App 路径> <版本> <输出目录>
set -euo pipefail
APP="$1"
VERSION="$2"
OUT="$3"
NAME="WageTick-$VERSION"

mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME.zip"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "牛马鼓励器" -srcfolder "$STAGE" -ov -format UDZO "$OUT/$NAME.dmg" >/dev/null
echo "$OUT/$NAME.zip"
echo "$OUT/$NAME.dmg"
