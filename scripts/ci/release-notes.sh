#!/bin/zsh
# 更新内容 (ADR-0007)：上一个同渠道版本到这次之间、改到 App 代码的提交标题，一行一条，去掉 feat: 之类的前缀。
# 只看 App 相关目录，CI、文档、脚本的提交不算；没有时写一句「细节优化与问题修复」。
# 用法：scripts/ci/release-notes.sh <上一个 tag，可为空> <这次的提交>
set -euo pipefail
PREVIOUS="${1:-}"
REF="$2"
RANGE="$REF"
[[ -n "$PREVIOUS" ]] && RANGE="$PREVIOUS..$REF"

notes=$(git log --no-merges --format=%s "$RANGE" -- WageTick WageCore WageTickWidgets Config WageTick.xcodeproj \
  | sed -E 's/^[a-z]+(\([^)]*\))?!?: //' \
  | awk '!seen[$0]++' \
  | head -n 12)
if [[ -z "$notes" ]]; then
  notes="细节优化与问题修复"
fi
print -r -- "$notes"
