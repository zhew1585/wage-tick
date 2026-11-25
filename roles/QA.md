# test guidelines
- 测试case必须包含2部分，函数范围的测试和功能范围的测试。
- 所有测试都在 homemac 上跑，见 TEAM.md「Machines」。

## 函数范围

`swift test --package-path WageCore`，全绿才算通过。
界面上显示的文字也由 WageCore 算好，文字类用例优先写成这里的断言。

## 功能范围

优先用离屏渲染看界面，假数据，不碰本机已装的 App 和用户数据：

- `scripts/render-panel-previews.sh`：今日概览各状态。
- `scripts/render-page-previews.sh`：历史、目标、设置等页面。
- `scripts/render-widget-previews.sh`：桌面小组件。

截图作为证据返回，和 `docs/assets/screenshots/` 里的现有截图对照。

菜单栏、悬浮小牛、通知、小组件刷新这类只有真跑才看得到的，用 `scripts/run-debug.sh`。
它会覆盖 `/Applications/牛马鼓励器.app` 并重启小组件服务，测完告诉 human 已被替换成 Debug 版。

## 用户数据

真实数据在 `~/Library/Application Support/com.zhew1585.WageTick/`。
要改数据造场景前先整目录备份，测完原样还原。
