#!/bin/zsh
# 离屏渲染桌面小组件三种尺寸的各个状态 (PNG)，和设计稿 (Pencil「macOS 桌面小组件」) 对照用。
# 不读写 state.json、widget.json，可以和正在跑的 App 同时用。做法见 WageTick/Widgets/WidgetPreviews.swift。
# 用法：scripts/render-widget-previews.sh [输出目录，默认 build/widget-previews]
set -euo pipefail
cd "$(dirname "$0")/.."
WAGETICK_RENDER_ENTRY=wagetick_render_widget_previews exec scripts/render-panel-previews.sh "${1:-build/widget-previews}"
