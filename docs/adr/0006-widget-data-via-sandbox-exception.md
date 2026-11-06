# 桌面小组件靠沙盒只读例外读 App 交的数据，不用 App Group

macOS 的小组件扩展必须开沙盒，而 App 不开沙盒、用 ad-hoc 签名 (`CODE_SIGN_IDENTITY = "-"`)，没有 Team ID。
App Group 的组名要带 Team ID 前缀 (macOS 15 起不带前缀的组名还要描述文件授权)，ad-hoc 签名拿不到，所以不走 App Group。
做法 (2026-11-06，待 Allen 确认)：

- App 每次落盘、换了节假日表时，把状态与节假日表写成 `~/Library/Application Support/com.zhew1585.WageTick/widget.json` (`WidgetPayload`，带版本号)，内容变了才写，写完让系统刷新小组件 (`WidgetBridge`)。
- 扩展的 entitlements 开沙盒，并用 `com.apple.security.temporary-exception.files.home-relative-path.read-only` 只读这一个目录；路径按真实主目录 (`getpwuid`) 算，不用沙盒里的 `NSHomeDirectory()`。
- 扩展读到数据后自己调核心的 `widgetTimeline` 排时间线，与 App 用同一套算法，小组件和面板不会不一致。

单独写一份 widget.json 而不是让扩展直接读 state.json：扩展不必知道状态文件的格式和节假日缓存、内置数据的位置，也不会碰到状态文件的迁移与损坏处理。
临时例外是 App Store 审核不接受的；以后要上架或换成正式签名，先回到这条 ADR，改成 App Group 容器。
