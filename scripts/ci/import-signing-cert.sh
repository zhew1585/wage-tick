#!/bin/zsh
# 把 Developer ID 证书导入一个临时钥匙串 (ADR-0009)，输出签名身份的 SHA-1，给 codesign-app.sh 和 dmg 签名用。
# 需要的环境变量 (来自仓库 secret)：DEVELOPER_ID_P12_BASE64、DEVELOPER_ID_P12_PASSWORD、APPLE_TEAM_ID。
# 钥匙串放在 $RUNNER_TEMP，随 GitHub 的临时虚拟机一起销毁。
# 用法：identity=$(scripts/ci/import-signing-cert.sh)
set -euo pipefail
: "${DEVELOPER_ID_P12_BASE64:?缺少 DEVELOPER_ID_P12_BASE64}"
: "${DEVELOPER_ID_P12_PASSWORD:?缺少 DEVELOPER_ID_P12_PASSWORD}"
: "${APPLE_TEAM_ID:?缺少 APPLE_TEAM_ID}"

DIR="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$DIR/signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
P12="$DIR/developer-id.p12"
# Developer ID 证书的中间证书；p12 里通常只有叶子证书，缺了它证书链不完整，find-identity 认为身份无效。
INTERMEDIATE="$DIR/DeveloperIDG2CA.cer"
trap 'rm -f "$P12"' EXIT

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

curl -fsSL --retry 5 --retry-delay 10 --retry-all-errors \
  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$INTERMEDIATE"
security import "$INTERMEDIATE" -k "$KEYCHAIN" >&2

print -rn -- "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$P12"
security import "$P12" -k "$KEYCHAIN" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign >&2
# 允许 codesign 不弹授权框直接用私钥。
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# 加进搜索列表，codesign 才找得到。
security list-keychains -d user -s "$KEYCHAIN" ${(f)"$(security list-keychains -d user | tr -d '" ')"}

identity=$(security find-identity -v -p codesigning "$KEYCHAIN" |
  awk -v team="($APPLE_TEAM_ID)" '/Developer ID Application/ && index($0, team) { print $2; exit }')
[[ -n "$identity" ]] || { print -u2 -- "钥匙串里没有 Team $APPLE_TEAM_ID 的有效 Developer ID Application 身份"; exit 1; }
print -- "$identity"
