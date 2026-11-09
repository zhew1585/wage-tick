#!/bin/zsh
# 编译 Debug 版，拷进 /Applications 再启动，桌面小组件才加得上、刷得出。
# 小组件服务 (chronod) 不认 build 目录里的 App (日志：Ignoring restricted or unknown extension)，只认 /Applications 那份；
# 本机同时登记多份同 bundle id 的 App 时又会挑错扩展，所以 build 目录那份拷完就注销，全机只留 /Applications 一份。
# 用法：scripts/run-debug.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="牛马鼓励器.app"
BUILT="build/dd/Build/Products/Debug/$APP_NAME"
INSTALLED="/Applications/$APP_NAME"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

xcodebuild -project WageTick.xcodeproj -scheme WageTick -configuration Debug -derivedDataPath build/dd \
    -destination "platform=macOS,arch=arm64" build -quiet

# 先退掉正在跑的 App 与小组件扩展，免得拷的时候还占着旧文件。
pkill -f "$APP_NAME/Contents/MacOS/WageTick\$" || true
pkill -f "WageTickWidgets.appex" || true
sleep 1

rm -rf "$INSTALLED"
ditto "$BUILT" "$INSTALLED"
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true
"$LSREGISTER" -f "$INSTALLED"

# 让小组件服务重新发现扩展，桌面上已放的小组件按新代码重画。
killall chronod NotificationCenter 2>/dev/null || true

open "$INSTALLED"
echo "已启动 $INSTALLED"
