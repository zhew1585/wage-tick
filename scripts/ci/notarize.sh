#!/bin/zsh
# 提交苹果公证并把票据钉进文件 (ADR-0009)，之后用 Gatekeeper 的规则验一遍，用户下载后双击就能打开。
# .app 先压成 zip 再提交 (公证只收 zip/dmg/pkg)，票据钉回 .app 本身；.dmg 直接提交并钉进 dmg。
# 需要的环境变量 (来自仓库 secret)：NOTARY_KEY_P8_BASE64、NOTARY_KEY_ID、NOTARY_ISSUER_ID (App Store Connect API Key)。
# 用法：scripts/ci/notarize.sh <App 或 dmg 路径>
set -euo pipefail
: "${NOTARY_KEY_P8_BASE64:?缺少 NOTARY_KEY_P8_BASE64}"
: "${NOTARY_KEY_ID:?缺少 NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?缺少 NOTARY_ISSUER_ID}"
TARGET="$1"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

KEY="$WORK/AuthKey.p8"
print -rn -- "$NOTARY_KEY_P8_BASE64" | base64 --decode > "$KEY"
auth=(--key "$KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")

case "$TARGET" in
  *.app)
    upload="$WORK/$(basename "$TARGET" .app).zip"
    ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$upload"
    assess=(--type execute) ;;
  *.dmg)
    upload="$TARGET"
    assess=(--type open --context context:primary-signature) ;;
  *) print -u2 -- "只支持 .app 或 .dmg：$TARGET"; exit 1 ;;
esac

# 苹果那边一般几分钟，偶尔排队更久。没通过时 notarytool 也可能返回 0，所以看结果里的 status。
result=$(xcrun notarytool submit "$upload" "${auth[@]}" --wait --timeout 1h --output-format json) || true
print -- "$result"
id=$(print -r -- "$result" | plutil -extract id raw -o - - 2>/dev/null || true)
st=$(print -r -- "$result" | plutil -extract status raw -o - - 2>/dev/null || true)
if [[ "$st" != "Accepted" ]]; then
  [[ -n "$id" ]] && xcrun notarytool log "$id" "${auth[@]}" || true
  print -u2 -- "公证没通过 (status: ${st:-未知})：$TARGET"
  exit 1
fi

xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
spctl --assess --verbose=2 "${assess[@]}" "$TARGET"
