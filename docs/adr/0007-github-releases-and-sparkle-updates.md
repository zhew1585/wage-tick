# 用 GitHub Actions 发 nightly 与正式版，App 内用 Sparkle 自动更新

Allen 想要和 pingdotgg/t3code 一样的发布方式：合进 main 的改动定期自动发 nightly，正式版手动发，装好的 App 自己检查并安装更新。
做法 (2026-11-09，Allen 定了 ad-hoc 签名、6 小时间隔、更新完自动重启，设置里可以切换接收尝鲜版)：

- 发布规则照搬 t3code (`.github/scripts/release-plan.cjs`)：
  - nightly：每 30 分钟检查一次，离上一个 nightly 满 6 小时、且 main 有新提交才发，打包当时 main 的最新提交。一个 nightly 就是「上一个 nightly 之后合进 main 的所有 PR」，不挑 PR。
  - 正式版：在 Actions 里手动运行 Release 并选 stable，打包最新一个 nightly 用的那个提交，只发 nightly 已经跑过的版本。
  - 版本号：最新正式版补丁号 +1 (还没有正式版时取工程的 `MARKETING_VERSION`)；nightly 再加「-nightly.日期.运行序号」，如 `0.1.1-nightly.20261109.42`。
  - 构建号 (`CFBundleVersion`) 用 Release 工作流的运行序号，一直递增，Sparkle 靠它比较新旧。
- 产物：GitHub Release 上一个 dmg (首次安装) 和一个 zip (Sparkle 下载)，发布说明由 GitHub 按上一个同渠道 tag 自动列出合进来的 PR。
- 更新清单：gh-pages 分支上的 `appcast.xml`，经 GitHub Pages 发布在 `https://zhew1585.github.io/wage-tick/appcast.xml`。nightly 条目带 `nightly` 渠道。
- App 内 (`AppUpdater`)：Sparkle 2，默认只收正式版，设置里打开「接收尝鲜版」后也收 nightly 渠道；默认每 6 小时检查一次、静默下载，下载完立即安装并重启 App，不等退出。
  设置页「更新」一组有当前版本、自动更新与接收尝鲜版两个开关和「检查更新」；主菜单有「检查更新…」。Debug 构建不检查更新，免得开发版被正式版覆盖。
  关掉接收尝鲜版不会降级：正式版是后来把某个 nightly 重新编译转正的，构建号更大，等它发出来自然升上去。
- 更新包用 Sparkle 的 EdDSA 密钥签名：私钥在 Allen 的钥匙串 (账户 wage-tick) 和仓库 secret `SPARKLE_PRIVATE_KEY`，公钥写在 `Config/WageTick-Info.plist`。
  私钥丢了就再也发不出旧版本能接受的更新，只能让大家手动重装。

代价：没有苹果开发者账号 (Developer ID)，App 只有 ad-hoc 签名，没做公证。
第一次从 GitHub 下载安装要在「应用程序」里右键 → 打开；之后的自动更新由 Sparkle 校验 EdDSA 签名后直接替换，不经过 Gatekeeper 的下载隔离。
以后买了 Developer ID，换成正式签名加公证即可，发布流程与 appcast 不用变。
