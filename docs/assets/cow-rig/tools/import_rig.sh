#!/bin/zsh
# 把一套拆好的小牛分层素材 (scaled/<层>.png 与 <层>@2x.png) 装进 Assets.xcassets/FloatingCow/<Name>Rig。
# 每层成为 imageset「Cow<Name><Layer>」(层名首字母大写)，代码里按这个名字取 (见 WageTick/FloatingCow/CowRigs.swift)。
# 用法：docs/assets/cow-rig/tools/import_rig.sh <scaled 目录> <Name>，如 import_rig.sh .../out/work/scaled Work
set -euo pipefail
SRC="$1"; NAME="$2"
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
DST="$ROOT/WageTick/Assets.xcassets/FloatingCow/${NAME}Rig"
rm -rf "$DST"; mkdir -p "$DST"
echo '{ "info" : { "author" : "xcode", "version" : 1 } }' > "$DST/Contents.json"
for one in "$SRC"/*@2x.png; do
  layer="$(basename "$one" @2x.png)"
  set="Cow${NAME}${(C)layer[1]}${layer[2,-1]}"
  file="$(echo "cow-${NAME}-${layer}" | sed -E 's/([A-Z])/-\1/g' | tr 'A-Z' 'a-z' | sed 's/--/-/g')"
  mkdir -p "$DST/$set.imageset"
  cp "$SRC/$layer.png" "$DST/$set.imageset/$file.png"
  cp "$one" "$DST/$set.imageset/$file@2x.png"
  cat > "$DST/$set.imageset/Contents.json" <<JSON
{
  "images" : [
    { "filename" : "$file.png", "idiom" : "universal", "scale" : "1x" },
    { "filename" : "$file@2x.png", "idiom" : "universal", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  echo "$set"
done
