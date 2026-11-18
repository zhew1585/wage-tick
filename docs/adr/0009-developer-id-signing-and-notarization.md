# 发布包用 Developer ID 签名并公证，编译仍是 ad-hoc

Allen 注册了苹果开发者账号，想让用户下载后直接双击打开，不再右键 → 打开。
光签名不够，Gatekeeper 还要看公证票据，所以发布时做三件事：Developer ID 签名、提交公证、把票据钉进 App 和 dmg。
做法 (2026-11-18)：

- 编译不变：工程仍是 ad-hoc 签名 (`CODE_SIGN_IDENTITY = "-"`)，本地、PR 检查 (`ci.yml`) 和发布用同一份构建配置，不用证书。
- 发布时 (`release.yml`) 在编译之后：
  1. `scripts/ci/import-signing-cert.sh` 把证书导入临时钥匙串，连同 Developer ID G2 中间证书。
  2. `scripts/ci/codesign-app.sh` 从内到外重签：Sparkle 内部组件与框架不带 entitlements (照 Sparkle 文档)；小组件扩展与 App 保留编译时的 entitlements，去掉公证不收的 `get-task-allow`，App 再去掉 `disable-library-validation`。
  3. 启动检查放在重签之后，库校验这时才真正生效。
  4. `scripts/ci/notarize.sh` 用 App Store Connect API Key 提交公证、等结果、钉票据，再用 `spctl` 按 Gatekeeper 规则验一遍。App 先公证，打包后 dmg 签名再公证一次。
- 用 ad-hoc 构建加重签，而不是 `xcodebuild archive` + `-exportArchive`：发布和 PR 检查编的是同一个东西，也不用为一处差别 (App 的 entitlements) 在工程里分配置。
- 证书与 Key 放在仓库 secret：`DEVELOPER_ID_P12_BASE64`、`DEVELOPER_ID_P12_PASSWORD`、`APPLE_TEAM_ID`、`NOTARY_KEY_P8_BASE64`、`NOTARY_KEY_ID`、`NOTARY_ISSUER_ID`。原件 Allen 自己备份。

已经装了 ad-hoc 版本的用户照常走 Sparkle 自动更新：Sparkle 2 允许更新换签名身份，只要 EdDSA 签名对得上。
Developer ID 证书 5 年到期，到期前在 Xcode 里新建一张，换掉两个 `DEVELOPER_ID_P12_*` secret；已发出去的版本带着签名时间戳，不受影响。
