#!/bin/zsh
# 离屏渲染今日概览面板与扣钱、请假表单的各个状态 (PNG)，和设计稿对照用。
# 不起菜单栏、不读写 state.json，可以和正在跑的 App 同时用。做法见 WageTick/Panel/PanelPreviews.swift。
# 用法：scripts/render-panel-previews.sh [输出目录，默认 build/panel-previews]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/panel-previews}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 加载时调用 App 里 Debug 才有的渲染入口，渲染完直接退出，App 的 main 不会跑。
cat > "$WORK/render.c" <<'C'
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

__attribute__((constructor)) static void render(void) {
    const char *dir = getenv("WAGETICK_RENDER_DIR");
    if (!dir) return;
    char exe[4096];
    uint32_t size = sizeof(exe);
    _NSGetExecutablePath(exe, &size);
    *strrchr(exe, '/') = 0;
    char lib[4200];
    snprintf(lib, sizeof(lib), "%s/WageTick.debug.dylib", exe);
    void *handle = dlopen(lib, RTLD_NOW);
    if (!handle) { fprintf(stderr, "%s\n", dlerror()); exit(2); }
    void (*entry)(const char *) = dlsym(handle, "wagetick_render_panel_previews");
    if (!entry) { fprintf(stderr, "没找到渲染入口，要用 Debug 构建\n"); exit(3); }
    entry(dir);
    exit(0);
}
C
clang -dynamiclib -o "$WORK/librender.dylib" "$WORK/render.c"

# 关掉 hardened runtime，DYLD_INSERT_LIBRARIES 才生效；产物放在临时目录，不碰正常构建。
xcodebuild -project WageTick.xcodeproj -scheme WageTick -configuration Debug -derivedDataPath "$WORK/dd" -destination "platform=macOS,arch=arm64" \
    ENABLE_HARDENED_RUNTIME=NO build -quiet
mkdir -p "$OUT"
WAGETICK_RENDER_DIR="$(cd "$OUT" && pwd)" DYLD_INSERT_LIBRARIES="$WORK/librender.dylib" \
    "$WORK/dd/Build/Products/Debug/WageTick.app/Contents/MacOS/WageTick"
