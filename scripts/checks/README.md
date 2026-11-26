# 界面规则检查

把 2026-11-25 至 26 还原旧版界面这几轮踩过的坑，落成每次都跑的硬性检查。
入口只有一个：`scripts/checks/run.sh`。

| 命令 | 跑什么 | 在哪跑 |
|---|---|---|
| `scripts/checks/run.sh static` | 自测，再查当前源码 | 哪里都行；CI「核心测试」里每次跑 |
| `scripts/checks/run.sh ui` | 渲染、量页头、真窗口与交互回归 | 要 macOS 与 Xcode；CI「App 编译与启动」里跑 |
| `scripts/checks/run.sh all` | 两样都跑 | 本机 Mac |

退出码：0 通过，1 有规则不过，2 blocked。
blocked 表示缺图、缺清单、缺工具，没法判断，不算通过。

## 文件

- `ui_lint.py`、`ui-lint.json`：静态规则，只读源码。
- `ui_geometry.py`、`ui-geometry.json`：读渲染图的像素量页头、认红绿灯、查空白图与产物清单。
- `selftest.py`：检查脚本自己的回归。
  每条静态规则配一处故意违规的改动，每条几何规则配一张现画的反例图，都必须被抓到。
  仓库里不放图片：反例图只有色块，位置取自当时真实渲染图上量到的数值，自测时画进临时目录。
- `ui-checks-mac.sh`：Mac 上的一次完整运行：编 Debug、离屏渲染、真窗口截图、交互回归、真实数据目录校验。
- `ui_drive.py`：拉起 App、截真窗口图、跑交互回归 (由 `ui-checks-mac.sh` 调用)。
- `harness/drive.m`：注入 Debug 版 App 的库，在 App 进程里合成按键与点击、截窗口图、读窗口状态与辅助功能树。
- `harness/FakeState.swift`：和核心源码一起编成小程序，用核心的公开命令造假状态。
- `selftest-mac.sh`：`ui-checks-mac.sh` 自己的回归，逐条做故意违规的源码改动，慢，不进 CI。

## 静态规则 (`ui_lint.py`)

| 规则 | 对应的坑 | 判定 | 误报边界 |
|---|---|---|---|
| RESTORE-BOLD | 第 2 版只换了配色，头图、胶囊按钮、展示字体都还在，被否 | 外壳里出现 `HeroTheme`、`BoldHero`、`.pill(`、`AppFont.heavy` 等，或打包了 Archivo Black、站酷字体，就不过 | 只查 `WageTick/`、`WageTickWidgets/`；核心里的同名数据不查 |
| RESTORE-EARNED | 「已到手」页先保留后被否 | 外壳里出现 `GoalEarned`、`showsEarned`、「已到手」就不过 | 注释里写这三个字也会报，外壳里本来就不该再提 |
| RESTORE-WINDOWS | 第 1 版要恢复三个独立窗口，被否 | 外壳里出现三个窗口控制器或 `PageWindow` 就不过 | 无 |
| CORE-KEPT | 还原界面时不能把核心的数据与计算一起删 | 核心里必须还有 `ui-lint.json` 列的 18 个符号；`@Test` 不少于 618 | 核心里改名要同步改清单；测试数是下限，只增不减 |
| COPY-LEAVE | 请假扣薪文字被改成「−¥1000」，Allen 定按原版「= ¥1000」 | `LeaveForm.deductionText` 必须是 `"= \(Format.money(…"` | 单元测试也断言了同一件事，这条是双保险 |
| HDR-CALLER | 页头在各页不一致；新页面漏掉 | 每处 `PageHeader(` 都要传 `back:`；目标、历史月列表、设置传 `isRoot: true`，月日历、单日详情不传；没登记的页面用了页头就不过 | 只认一行写完的调用；换行写要调整规则 |
| HDR-TITLEBAR | 页头排在红绿灯下面多出的一行里，看着偏下 | 今日概览窗口用 `.tall` (52)；概览内容从 28 排起；页头高度取 `.tall`；页面预览上方不另留一行 | 标题栏方案变了要改规则；现方案 Allen 2026-11-26 00:38 已接受 |
| NAV-COVER | 页面盖着时底下的概览还能点、能聚焦；钉住按钮叠在滑动的页头上 | `TodayPanelView` 的 `body` 里必须有 `.disabled(content.page != nil)`、`.accessibilityHidden(…)`、`PinButton(`；控制器里不能有 `PinButton(` | 只看写法，真实效果由交互回归与人工确认 |
| NAV-ESC | Esc 兜底直接跳回概览或关窗；请假表单过零点后第一次 Esc 白按 | `handleCancel()` 里要先 `goBackInside(page)`、要处理 `content.route != .home`；`refresh()` 里请假表单没了要回概览 | 同上 |
| NAV-SHEET | 开着弹出表单时 ⌘1 ⌘2 ⌘3 ⌘, 会退页或换页，没填完的丢了 | `show()` 里 `push(page)` 与 `pop()` 都要受 `hasSheet` 保护 | 同上 |
| NAV-DOCK | 点 Dock 图标把人从页面踢回概览 | `applicationShouldHandleReopen` 里必须是 `show(returnsToOverview: false)` | 同上 |
| NAV-GOALCARD | 还原后概览上累计中目标的卡片点不了 | `GoalCardView` 的 `.active` 分支必须包 `Button(action: openGoals)` | 同上 |
| NAV-HISTORY | 历史页返回时内容先消失；进来不是月列表 | `disappear()` 里不能清空快照与选中项；`appear()` 里要重置；要有 `goBack()` | 同上 |
| NAV-TIMER | 页面退出去后发命令，把停掉的定时器又拉起来 | `HistoryPage`、`GoalsPage` 的 `refresh()` 里要有 `guard isActive else { return }` | 同上 |
| REPO-LOCAL | `roles/`、`docs/spec/` 只放本机 | `git ls-files roles docs/spec` 必须为空 | 不在 git 仓库里时不查 |

成功路径：`python3 scripts/checks/ui_lint.py` 在当前源码上输出「ui_lint: 通过」，退出码 0。
故意违规：`selftest.py` 里的 20 处改动，每处都必须让 `ui_lint.py` 以退出码 1 报出对应规则。

静态规则看的是源码的写法，能挡住「改回去」，挡不住「换一种写法写错」。
导航那几条的真实行为，靠下面的交互回归与人工验收。

## 几何与产物规则 (`ui_geometry.py`)

图是 2 倍。
离屏预览 816 px 宽，四周留 24 pt 白边；真窗口图 720 px 宽，没有白边。
坐标都换算成相对窗口左上角的 pt。
「墨迹」指亮度低于 110 的像素，也就是墨色的箭头与标题；灰色的说明文字不算。

| 规则 | 对应的坑 | 适用的图 | 判定与阈值 | 误报边界 |
|---|---|---|---|---|
| HDR-FRAME | 页头排在多出的一行里 (`73f794d`) | 目标、历史、设置、月日历、单日详情 | 页头分隔线在 52 pt ±1.5 | 页头下沿换了颜色要调亮度范围 |
| HDR-BACK | 推进来的页面没有返回 | 同上 | 页头里第一段墨迹宽不超过 9 pt，且后面还有标题 | 标题第一个字很窄 (如「一」) 时可能被当成箭头 |
| HDR-VCENTER | 返回与标题偏下 | 同上 | 墨迹中心偏离页头框中心不超过 1 pt；真窗口图上红绿灯中心与标题中心相差不超过 1 pt | 原版月日历是 +0.5 |
| HDR-LIGHTS-GAP | 箭头离红绿灯 6 pt，Allen 说太近 (`84b2b71`) | 同上 | 箭头墨迹左沿到红绿灯右沿 (72) 必须大于 6 | 6 是被否掉的值，不是合格线；合格看 HDR-X 与人工 |
| HDR-X | 标题比原版靠右 26 (`947880d`)；三处间距压在边界上 | 目标、目标空状态、历史月列表、设置 | 箭头左沿 85 ±1；箭头到标题 7.5 至 12 (各字左侧留白不同，「目」最宽)；标题左沿不超过 105 | 85 是 `d107b63` 的设计值，Allen 看过真窗口图后若调整，要改 `ui-geometry.json` |
| HDR-X | 下一级页头要保持原版 | 月日历、单日详情 | 箭头左沿 90 ±1；箭头到标题 13 至 18；标题左沿不超过 114 | 原版实测值 |
| HDR-CONSISTENT | 目标、历史、设置的页头不一致 | 同一类的几页之间 | 箭头左沿相差不超过 0.5；墨迹中心 y 相差不超过 0.75 | 无 |
| HDR-LIGHTS | 标题栏方案被悄悄改掉 | 真窗口图 | 三个红绿灯右沿在 72 ±1.5，中心 y 在 26 ±1 | 系统换了红绿灯尺寸要重新量；找圆的范围从左上 4pt 起，标题栏改回 28 高 (红绿灯在 8–60、中心 14) 时也能找到并报这一条 |
| IMG-BLANK | 近景裁成了空白图还照样提交 (`3d73c4c`) | 所有图 | 与底色不同的像素不到 0.3% 就不过 | 只看图的上部 |
| IMG-KIND | 离屏预览不画红绿灯，不能冒充真窗口图 | 所有图 | 标成离屏的图里不能有红绿灯；标成真窗口的必须有三个；页面图与真窗口图的图宽要对得上 | 认的是红绿灯的位置与大小，不认颜色；离屏预览里的弹出表单本来就比窗口窄，不查图宽，也不找红绿灯 (表单标题的字会被认成圆) |
| IMG-VERSION | 拿旧提交的图当新图 | 带清单的整套图 | `manifest.json` 里的提交必须是当前 `HEAD` | 清单要由出图的脚本写 |
| IMG-MANIFEST | 图没标明版本、时间、截法 | 同上 | 清单必须有 `commit`、`kind`、`capturedAt`、`method`、`files` | 无 |
| BLOCKED | 缺图、缺清单时当成通过 | 同上 | 整套检查不给清单、清单里的图不在、该有的图缺了，都退出码 2 | 真窗口图里月日历等几页可以没有，会记一行 MANUAL |

成功路径：`python3 scripts/checks/ui_geometry.py --kind offscreen --dir <页面预览目录> --manifest <清单>` 输出「ui_geometry: 通过」，退出码 0。
故意违规：`selftest.py` 按下表现画反例图，确认每张都被对应的规则抓到。

| 反例 | 位置数值来自 | 必须被抓到 |
|---|---|---|
| 页头排在多出的一行里：分隔线 79，没有箭头 | `73f794d` 的渲染图 | HDR-FRAME |
| 标题比原版靠右 26：箭头 90，标题 114 | `947880d` 的渲染图 | HDR-X |
| 箭头离红绿灯 6：箭头 78，离屏与真窗口各一 | `84b2b71` 的渲染图与真窗口图 | HDR-LIGHTS-GAP、HDR-X |
| 页头没有箭头 | 构造 | HDR-BACK |
| 返回与标题偏下 3 | 构造 | HDR-VCENTER |
| 目标与历史的箭头差 1 | 构造 | HDR-CONSISTENT |
| 红绿灯在 8 至 60、中心 14 | 28 高标题栏的系统位置 | HDR-LIGHTS |
| 只有底色的图 | `3d73c4c` 里裁成空白的近景 | IMG-BLANK |
| 图宽对不上；离屏宽的图里有红绿灯；真窗口宽的图里没有 | 构造 | IMG-KIND |
| 清单里的提交不是 `HEAD`，还缺 `method` | 构造 | IMG-VERSION、IMG-MANIFEST |
| 不给清单；缺图 | 构造 | BLOCKED (退出码 2) |

必须放行的：原版月日历页头 (`9c69fd3`：箭头 90 至 96.5，标题 112)；当前设计的首页页头 (`d107b63`：箭头 85 至 91.5，离红绿灯 13)，离屏与真窗口各一组。
还有比窗口窄的弹出表单图：表单标题的三个字正好在红绿灯的位置上，不能被认成红绿灯 (几何检查头一回在整套渲染图上跑时把它们误报成 IMG-KIND)。
反例图没有抗锯齿和真实字形，只验证规则的判定；对真实渲染的判定由 `run.sh ui` 在当前提交上跑、由 `selftest-mac.sh` 做故意违规。

### 关于美观

HDR-LIGHTS-GAP 只保证不退回被 Allen 否掉的 6 pt。
HDR-X 只保证和当前的设计值一致，不代表这个设计值已经被认可。
留白是否美观，要 Allen 看真窗口图确认；检查每次都会打印这一句。

## 交互回归 (`ui-checks-mac.sh`、`ui_drive.py`)

### 一次运行做什么

1. 前置：不是 macOS，或缺 `xcodebuild`、`python3`、`clang`、`swiftc`、`shasum`，报 BLOCKED 退出 2。
2. 编一次 Debug (`ENABLE_HARDENED_RUNTIME=NO`，构建目录在 `mktemp -d` 里)，离屏渲染与真窗口都用这一份；编译失败记 `FAIL [BUILD]`，退出 1。
3. 编注入库 `harness/drive.m`，用 `harness/FakeState.swift` 造假状态。
   假状态：上个月 1 号完成引导，月薪 20000，10:00–18:00，饭点 12:00–13:00，双休；关掉桌面悬浮小牛与两种通知；一个累计中目标「换台 MacBook」加四个排队目标，金额远大于两个月工资，不会弹庆祝动画。
   今天设成上班日，周末、节假日、深夜跑，概览上都有「今天扣钱了」。
4. 离屏渲染：注入库调用 `wagetick_render_page_previews`，图放 `offscreen/`，写清单 (`kind: offscreen`，`decorations` 里窗框与红绿灯都是 false)，跑 `ui_geometry.py --kind offscreen`。
5. 真窗口与交互回归：`ui_drive.py` 用假主目录拉起 App (`CFFIXED_USER_HOME` 加注入库里拦截 `getpwuid`)，经 Unix 套接字给注入库发命令。
   截 `today`、`P3-goals`、`P4-history`、`P5-calendar`、`P5-day-detail`、`P6-settings` 六张真窗口图放 `realwindow/`，写清单 (`method: cacheDisplay`，`active` 按实际)，跑 `ui_geometry.py --kind realwindow`。
6. 真实数据目录 `~/Library/Application Support/com.zhew1585.WageTick/` 在开始前、结束后各取一次校验和 (文件名加内容)，变了记 `FAIL [ENV-DATA]`。
7. 收尾：只关自己拉起的 App (先在进程内 `NSApp terminate:`，10 秒不退就杀它的 pid)，删临时目录。

输出目录默认 `build/ui-checks/`，可用第一个参数或环境变量 `UI_CHECKS_OUT` 改。
里面留离屏图、真窗口图、两份清单、`ui-checks.log`、`app.log`、编译日志，规则不过时还有 `fail-<规则>-<序号>.png`，是当时的整窗图。
本机一次完整运行约 90 秒 (含 Debug 编译)。

### 怎么驱动

注入库在 App 进程里做这些事，不走系统的事件注入，不需要辅助功能、屏幕录制授权：

- 按键：合成 `NSEvent` 键盘事件，`NSApp postEvent:` 排进 App 自己的事件队列，和真按键一样先给 key 窗口、再给主菜单的快捷键。
- 点击：合成鼠标按下、抬起，同样排进事件队列。
  点哪里由辅助功能树决定：注入库在进程内打开 `AXEnhancedUserInterface`，SwiftUI 才会建树，再按按钮的文字 (如「新目标」「今天扣钱了」) 读出它在窗口里的位置。
- 截图：对窗框视图 (含系统红绿灯) 调 `cacheDisplay(in:to:)`，按 2 倍画，圆角外铺窗口底色。
- 窗口状态：`isVisible`、`attachedSheet`、窗口编号、可见的带标题窗口。
- 点 Dock 图标：直接调 `applicationShouldHandleReopen(_:hasVisibleWindows:)`，系统点 Dock 图标时调的就是它。

App 拿不到前台，红绿灯是灰的，窗口也不是 key 窗口；这对上面的判定没有影响。

### 怎么认页

- 页面：页头区域 (窗口顶部 4–44pt、x 76pt 往右) 的墨迹指纹与参照逐像素相同。
  墨迹指纹是亮度低于 160 的像素组成的形状的哈希，只看深色的字与图标；悬停、按下时浅色的圆角底与红绿灯的颜色不影响。
  参照是本次运行里截的：⌘2、⌘3、⌘, 截下目标、历史月列表、设置，第一次点进月日历、单日详情时截下这两页。
  概览的日期时钟从 46pt 起，滚动的金额更靠下，都不在这块区域里。
- 概览：底部入口栏 (最下面 46pt，历史、目标、设置那一条) 的墨迹指纹与启动时的参照相同。
  推进来的页面和扣钱、请假表单都会把它盖住或换掉。
- 每次动作后等画面停下：两块区域的指纹连续两次相同 (至少等 0.45 秒，最多 4 秒)。
- ACT-PUSH 另外核对辅助功能树里页头按钮的文字是「目标」「历史」「设置」，并用 `ui_geometry.measure_header` 确认页头里有返回箭头。

### 规则

| 规则 | 对应的坑 | 步骤 | 判定 | 误报边界 |
|---|---|---|---|---|
| ACT-PUSH | 目标、历史、设置要在同一个窗口里推进来 | 概览上依次按 ⌘2、⌘3、⌘, | 窗口编号不变、只有这一个带标题的窗口；页头指纹与之前的每一页都不同、底栏不见了；页头按钮文字对；有返回箭头 | 三页的参照就在这一步截；这一条不过时，后面靠参照认页的规则跟着不可信，以这一条为准 |
| ACT-DOCK | 点 Dock 图标被踢回概览 | ⌘1 回概览，⌘, 进设置，触发重新打开 | 仍是设置页 | 直接调代理方法，不经过 Dock 本身 |
| ACT-HOME | 停在页面上按 ⌘1 不回概览 | ⌘2 进目标页，按 ⌘1 | 是概览 | 其他规则都用 ⌘1 回概览作起点，这条坏了它们会跟着一起报 |
| ACT-GOALCARD | 概览目标卡点不了 | 在概览上点「换台 MacBook」(卡片是按钮时点整张卡的中心，不是按钮时点名字那一行字) | 进了目标页 | 只点累计中目标的卡片，空状态卡与排队行不点 |
| ACT-COVER | 页面盖着时点得到底下 | 先在概览上记下「今天扣钱了」的位置，⌘2 进目标页，在那个位置点一下，再按 ⌘1 | 点完仍是目标页、没有弹出表单；⌘1 后是概览 (底栏还在)，不是扣钱表单 | 页面整块铺了底色，点击被页面接住，去掉底层的 `.disabled` 时点不穿，这条抓不到 (见实测)；它只保证点击不会漏到底下，Tab 与辅助功能那一半靠静态规则 NAV-COVER |
| ACT-SHEET | 开着表单时快捷键把页面换掉 | 目标页点「新目标」，依次按 ⌘1、⌘2、⌘3、⌘,，再按 Esc | 每按一次 `attachedSheet` 仍在、页头指纹与刚弹出表单时相同 (挂着表单时窗口整体压暗，所以用这时截的参照)；Esc 后 `attachedSheet` 为空且是目标页 | 无 |
| ACT-ESC | Esc 跳级或提前关窗 | ⌘3 进月列表，点第一个月份行，点第一个有工资的日子，然后按 4 次 Esc | 依次是月日历、月列表、概览，窗口一直可见；第 4 次后窗口不可见 | 每一级的 Esc 都先被页头返回按钮的快捷键接走，窗口的 Esc 兜底 (`handleCancel`) 走不到；兜底改坏了这条抓不到 (见实测)，只有静态规则 NAV-ESC 能抓 |
| ACT-HISTORY | 历史页再进来不是月列表 | 同上进到单日详情，按 ⌘1，再按 ⌘3 | ⌘1 后是概览；⌘3 后是月列表 | 无 |
| ENV-DATA | 检查碰了真实数据 | 开始前、结束后各取一次真实数据目录的校验和 | 前后一致 | 本机另开着一个 App 时它自己会写这个目录，这时记 BLOCKED，不记 FAIL |

规则不过时打印 `FAIL [规则] <现象> (当时的窗口图：…)`，整次运行退出 1。
窗口在 60 秒内没出现、驱动连不上、App 中途崩了、启动后不在概览、假状态下没有「今天扣钱了」，都是 BLOCKED，退出 2。
全部通过时每条规则打一行 `ok [规则] …`，几何规则离屏、真窗口各一组。

### `selftest-mac.sh`：故意违规必须被抓到

`scripts/checks/selftest-mac.sh` 在临时 worktree 里 (检出当前提交，再盖上工作区的 `scripts/checks/`) 先跑一遍不改的，必须通过；然后逐条改源码、跑 `run.sh ui`、还原。
慢 (十几分钟)，不进 CI；改了检查脚本或页面结构后在本机跑。
`scripts/checks/selftest-mac.sh <文字>` 只跑名字里含这段文字的改动。
源码变了、找不到要改的原文时报 BLOCKED，要同步改脚本里的 `CASES`。

实测 (2026-11-26，提交 023eb31 加本次的检查脚本，本机 Apple Silicon Mac；每条约 90 秒，整轮约 16 分钟)：

| 改动 | 改了什么 | 预期规则 | 退出码 | 实际报出 | 抓到 |
|---|---|---|---|---|---|
| 箭头离红绿灯 6pt | `PageHeader.rootLeading` 改回 `leadingInset - Spacing.s6` | HDR-LIGHTS-GAP 或 HDR-X | 1 | HDR-LIGHTS-GAP、HDR-X | 是 |
| 窗口改回标准标题栏 | 今日概览窗口 `titlebar: .standard` | HDR-LIGHTS 或 HDR-VCENTER | 1 | HDR-LIGHTS、HDR-VCENTER | 是 |
| 页面预览上方多留一行 | `PagePreviews.page()` 上方加 28 的 padding | HDR-FRAME | 1 | HDR-FRAME、HDR-VCENTER | 是 |
| 盖页后底层没停用 | `TodayPanelView` 去掉 `.disabled(content.page != nil)` | ACT-COVER | 0 | 无 | 否 |
| 开着表单也换页 | `show()` 里 `push` 不再受 `hasSheet` 保护 | ACT-SHEET | 1 | ACT-SHEET | 是 |
| Esc 兜底直接退回概览 | `handleCancel()` 里 `if !goBackInside(page) { pop() }` 改成 `pop()` | ACT-ESC | 0 | 无 | 否 |
| 概览目标卡不可点 | `GoalCardView` 的累计中卡片去掉 `Button` 包裹 | ACT-GOALCARD | 1 | ACT-GOALCARD | 是 |
| 点 Dock 图标也退页 | `applicationShouldHandleReopen` 改回 `todayPanel.show()` | ACT-DOCK | 1 | ACT-DOCK | 是 |
| ⌘1 不回概览 | `show()` 里去掉 `pop()` 那个分支 | ACT-HOME | 1 | ACT-HOME，另有 ACT-COVER、ACT-DOCK、ACT-ESC、ACT-GOALCARD、ACT-HISTORY、ACT-SHEET 跟着报 (它们都用 ⌘1 回概览作起点) | 是 |
| 历史页再进来不是月列表 | `HistoryPage.appear()` 不重置 `selectedMonth`、`selectedDay` | ACT-HISTORY | 1 | ACT-HISTORY | 是 |

10 条里抓到 8 条。
没抓到的两条，界面上确实看不出差别，不是检查漏看：

- 去掉 `.disabled`：推进来的页面整块铺了底色，点击落在页面上，点不到底下的概览；`.accessibilityHidden` 也还在。
  差别只在键盘 Tab 能不能聚焦到底下，交互回归不按 Tab (App 拿不到前台，没有焦点环)。
  这一处只有静态规则 NAV-COVER 能抓，Tab 的行为留给人工验收。
- Esc 兜底：每一级页面的 Esc 都先被页头返回按钮的快捷键 (`.keyboardShortcut(.cancelAction)`) 接走，正常操作走不到 `handleCancel()`。
  这条违规靠 ACT-ESC 抓不到，只有静态规则 NAV-ESC 能抓。

第一轮实测里「窗口改回标准标题栏」只报出 IMG-KIND：`measure_lights` 从左上 12pt 起找圆，28 高标题栏的第一个红绿灯 (8–20) 被切掉了。
找圆的范围改成从 4pt 起后，报的是 HDR-LIGHTS、HDR-VCENTER；阈值没有动。

## 不能自动覆盖的，需要人工验收

下面这些自动检查替代不了，合并前要有人在真机上看一遍。

- Tab 切焦点时是否落到被盖住的概览上：App 拿不到前台，没有键盘焦点环，交互回归不按 Tab。
- 输入框里、中文输入法选词时按 Esc 的归属：交互回归只在没有输入焦点时按 Esc。
- 真人用鼠标键盘操作的手感：悬停、拖动排序、滑入滑出的动画过程；检查只看动画停下后的画面。
- 从菜单栏小牛的菜单、悬浮小牛、系统通知打开页面：交互回归只走主菜单快捷键与概览上的按钮。
- 真的点 Dock 图标：交互回归直接调系统会调的代理方法，不经过 Dock。
- App 在前台时红绿灯的颜色：自动截的图是非激活态，红绿灯是灰的。
- 窗口阴影与圆角：进程内截图不带阴影，圆角外铺的是窗口底色。
- 1 倍屏上的像素取整：截图一律按 2 倍画。
- 目标空状态、月日历的其他月份、单日详情的各种状态在真窗口里的样子：真窗口图只截六张，其余只有离屏预览，`ui_geometry.py` 会逐张打 MANUAL。
- 留白是否美观。
- 与原版逐像素一致：基准图不在仓库里，每次重渲原版太慢，这一项靠出图时的像素比对报告。
- GitHub 托管的 runner 上能不能拉起窗口还没验证过；拉不起来时这一步会报 BLOCKED (退出码 2)，不会当作通过。
